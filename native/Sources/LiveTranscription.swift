@preconcurrency import AVFoundation
import Foundation
import Observation
import Speech
import UIKit
import os

/// Owns one foreground, on-device transcription session.
///
/// This controller intentionally never creates an audio file. Microphone buffers are converted
/// in memory and passed directly to `SpeechAnalyzer` through a bounded stream.
@MainActor
@Observable
final class LiveTranscription {
    enum State: Equatable, Sendable {
        case idle
        case preparing
        case downloadingAssets
        case requestingPermission
        case listening
        case finalizing
        case stopped
        case interrupted
        case unavailable
        case failed
    }

    private(set) var state: State = .idle
    private(set) var status = "Ready for on-device transcription."
    private(set) var finalized = ""
    private(set) var volatile = ""
    private(set) var errorMessage: String?
    private(set) var shouldOfferMicrophoneSettings = false
    private(set) var assetDownloadProgress: Progress?

    var transcript: String { finalized + volatile }
    var isListening: Bool { state == .listening }
    var isBusy: Bool {
        if cleanupQuarantineTask != nil { return true }
        return switch state {
        case .preparing, .downloadingAssets, .requestingPermission, .listening, .finalizing:
            true
        default:
            false
        }
    }

    private static let audioBufferLimit = 24
    private static let tapBufferSize: AVAudioFrameCount = 4_096
    /// AVAudioEngine may hand the tap more frames than the size that was requested, so pooled
    /// capture buffers are allocated with headroom instead of exactly `tapBufferSize`.
    private static let tapCapacityHeadroom: AVAudioFrameCount = 4
    private static let engineReconnectWindow: Duration = .seconds(1)
    private static let engineReconnectLimit = 5
    private static let conversionDrainTimeout: Duration = .seconds(2)
    private static let analyzerFinishTimeout: Duration = .seconds(5)
    private static let resultDrainTimeout: Duration = .seconds(2)
    private static let assetReleaseTimeout: Duration = .seconds(2)

    private var audioEngine = AVAudioEngine()
    private let audioSession = AVAudioSession.sharedInstance()
    private var transcriber: LiveTranscriberSelection?
    private var analyzer: SpeechAnalyzer?
    private var audioBridge: LiveAudioInputBridge?
    private var resultTask: Task<Void, Never>?
    private var shutDownTask: Task<LiveTranscriptionShutDownOutcome, Never>?
    private var shutDownRunID: UUID?
    private var cleanupQuarantineTask: Task<Void, Never>?
    private var cleanupQuarantineID: UUID?
    private var notificationTokens: [NSObjectProtocol] = []
    private var tapInstalled = false
    private var tapFormat: AVAudioFormat?
    private var ownedReservedLocale: Locale?
    private var audioEngineIsInvalidated = false
    private var engineReconnects = 0
    private var lastEngineReconnect: ContinuousClock.Instant?
    private var runID: UUID?

    /// Starts a new transcription session. Call this only after presenting any required
    /// participant disclosure and collecting the user's confirmation.
    func start(locale requestedLocale: Locale = .current, clearTranscript: Bool = true) async {
        guard !isBusy else { return }

        let id = UUID()
        runID = id
        state = .preparing
        status = "Preparing on-device transcription…"
        errorMessage = nil
        shouldOfferMicrophoneSettings = false
        assetDownloadProgress = nil
        if clearTranscript {
            finalized = ""
            volatile = ""
        }

        do {
            let selection = try await selectTranscriber(for: requestedLocale)
            let locale = selection.locale
            let modules: [any SpeechModule] = [selection.module]
            try ensureCurrentRun(id)

            transcriber = selection
            try await ensureAssets(for: modules, locale: locale, runID: id)
            try ensureCurrentRun(id)

            state = .requestingPermission
            status = "Waiting for microphone permission…"
            guard await requestMicrophonePermission() else {
                throw LiveTranscriptionError.microphoneDenied
            }
            try ensureCurrentRun(id)

            let analyzer = SpeechAnalyzer(modules: modules)
            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: modules
            ) else {
                throw LiveTranscriptionError.noCompatibleAudioFormat
            }
            try ensureCurrentRun(id)

            let bridge = LiveAudioInputBridge(
                outputFormat: analyzerFormat,
                bufferLimit: Self.audioBufferLimit
            ) { [weak self] failure in
                Task { @MainActor [weak self] in
                    await self?.handleAudioFailure(failure, runID: id)
                }
            }

            self.analyzer = analyzer
            audioBridge = bridge
            resultTask = makeResultTask(for: selection, runID: id)
            try await analyzer.start(inputSequence: bridge.analyzerInputs)
            try ensureCurrentRun(id)

            engineReconnects = 0
            lastEngineReconnect = nil
            installInterruptionObservers(for: id)
            try configureAudioSession()
            try startAudioEngine(with: bridge)
            try ensureCurrentRun(id)

            state = .listening
            status = "Listening on this device. Audio is not saved."
        } catch is CancellationError {
            await abandon(runID: id)
        } catch {
            await fail(error, runID: id)
        }
    }

    /// Stops microphone capture and waits for SpeechAnalyzer to finalize its last volatile result.
    func stop() async {
        if state == .finalizing {
            if let shutDownTask {
                _ = await shutDownTask.value
            }
            return
        }
        guard let id = runID else {
            if state == .idle {
                state = .stopped
                status = "Transcription is stopped."
            }
            return
        }

        if state == .listening {
            state = .finalizing
            status = "Finishing the transcript…"
            do {
                try await shutDown(runID: id, finalize: true, waitForResultTask: true)
                guard runID == id else { return }
                runID = nil
                volatile = ""
                state = .stopped
                status = "Transcription stopped. Audio was not saved."
            } catch {
                completeFailure(error, runID: id)
            }
        } else {
            state = .finalizing
            status = "Stopping transcription…"
            assetDownloadProgress?.cancel()
            await shutDownWithoutThrowing(runID: id, finalize: false, waitForResultTask: true)
            guard runID == id else { return }
            runID = nil
            state = .stopped
            status = "Transcription is stopped."
        }
    }

    func resetTranscript() {
        guard !isBusy else { return }
        finalized = ""
        volatile = ""
        errorMessage = nil
        shouldOfferMicrophoneSettings = false
        state = .idle
        status = "Ready for on-device transcription."
    }

    private func selectTranscriber(for requestedLocale: Locale) async throws
        -> LiveTranscriberSelection
    {
        let speechTranscriberAvailable = SpeechTranscriber.isAvailable
        if speechTranscriberAvailable,
           let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale)
        {
            return .speech(
                SpeechTranscriber(locale: locale, preset: .progressiveTranscription),
                locale
            )
        }

        if let locale = await DictationTranscriber.supportedLocale(equivalentTo: requestedLocale) {
            return .dictation(
                DictationTranscriber(locale: locale, preset: .progressiveLongDictation),
                locale
            )
        }

        if speechTranscriberAvailable {
            throw LiveTranscriptionError.localeUnsupported
        }
        throw LiveTranscriptionError.transcriberUnavailable
    }

    private func ensureAssets(
        for modules: [any SpeechModule],
        locale: Locale,
        runID id: UUID
    ) async throws {
        let ownsReservation: Bool
        do {
            ownsReservation = try await AssetInventory.reserve(locale: locale)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LiveTranscriptionError.assetInstallationFailed
        }

        do {
            try ensureCurrentRun(id)
        } catch {
            if ownsReservation {
                _ = await AssetInventory.release(reservedLocale: locale)
            }
            throw error
        }
        if ownsReservation {
            ownedReservedLocale = locale
        }

        switch await AssetInventory.status(forModules: modules) {
        case .installed:
            return
        case .unsupported:
            throw LiveTranscriptionError.localeUnsupported
        case .supported, .downloading:
            state = .downloadingAssets
            status = "Downloading on-device language assets…"
            guard let request = try await AssetInventory.assetInstallationRequest(
                supporting: modules
            ) else {
                break
            }
            assetDownloadProgress = request.progress
            try await request.downloadAndInstall()
            try ensureCurrentRun(id)
        @unknown default:
            throw LiveTranscriptionError.assetInstallationFailed
        }

        guard await AssetInventory.status(forModules: modules) == .installed else {
            throw LiveTranscriptionError.assetInstallationFailed
        }
        assetDownloadProgress = nil
    }

    private func requestMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    // SpeechAnalyzer performs this transcription on device. Unlike the legacy
    // SFSpeechRecognizer path, it does not require SFSpeechRecognizer authorization.
    private func configureAudioSession() throws {
        try audioSession.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: .allowBluetoothHFP
        )
        // `notifyOthersOnDeactivation` only applies when a session is deactivated.
        try audioSession.setActive(true)
    }

    private func startAudioEngine(with bridge: LiveAudioInputBridge) throws {
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw LiveTranscriptionError.noAudioInput
        }
        // Drop the old tap before swapping the capture pool so the render thread never reads
        // a pool that is being replaced during a reconnect.
        if tapInstalled {
            input.removeTap(onBus: 0)
            tapInstalled = false
        }
        try bridge.prepareCapture(
            format: format,
            frameCapacity: Self.tapBufferSize * Self.tapCapacityHeadroom,
            bufferCount: Self.audioBufferLimit + 2
        )

        input.installTap(
            onBus: 0,
            bufferSize: Self.tapBufferSize,
            format: format
        ) { buffer, _ in
            bridge.receive(buffer)
        }
        tapInstalled = true
        tapFormat = format
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            tapInstalled = false
            tapFormat = nil
            throw error
        }
    }

    private func makeResultTask(
        for selection: LiveTranscriberSelection,
        runID id: UUID
    ) -> Task<Void, Never> {
        switch selection {
        case .speech(let transcriber, _):
            makeResultTask(for: transcriber, runID: id)
        case .dictation(let transcriber, _):
            makeResultTask(for: transcriber, runID: id)
        }
    }

    private func makeResultTask(
        for transcriber: SpeechTranscriber,
        runID id: UUID
    ) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            do {
                for try await result in transcriber.results {
                    guard !Task.isCancelled else { return }
                    self?.accept(result, runID: id)
                }
                guard let self, self.runID == id, self.state != .finalizing else { return }
                await self.fail(
                    LiveTranscriptionError.recognitionFailed,
                    runID: id,
                    originatingFromResultTask: true
                )
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.runID == id, self.state != .finalizing else { return }
                await self.fail(
                    LiveTranscriptionError.recognitionFailed,
                    runID: id,
                    originatingFromResultTask: true
                )
            }
        }
    }

    private func makeResultTask(
        for transcriber: DictationTranscriber,
        runID id: UUID
    ) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            do {
                for try await result in transcriber.results {
                    guard !Task.isCancelled else { return }
                    self?.accept(
                        text: String(result.text.characters),
                        isFinal: result.isFinal,
                        runID: id
                    )
                }
                guard let self, self.runID == id, self.state != .finalizing else { return }
                await self.fail(
                    LiveTranscriptionError.recognitionFailed,
                    runID: id,
                    originatingFromResultTask: true
                )
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.runID == id, self.state != .finalizing else { return }
                await self.fail(
                    LiveTranscriptionError.recognitionFailed,
                    runID: id,
                    originatingFromResultTask: true
                )
            }
        }
    }

    private func accept(_ result: SpeechTranscriber.Result, runID id: UUID) {
        accept(
            text: String(result.text.characters),
            isFinal: result.isFinal,
            runID: id
        )
    }

    private func accept(text: String, isFinal: Bool, runID id: UUID) {
        guard runID == id else { return }
        if isFinal {
            finalized.append(text)
            volatile = ""
        } else {
            volatile = text
        }
    }

    private func installInterruptionObservers(for id: UUID) {
        removeInterruptionObservers()
        let center = NotificationCenter.default

        notificationTokens.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] notification in
                let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
                Task { @MainActor [weak self] in
                    await self?.interrupt(
                        "Transcription stopped because another audio session interrupted the microphone.",
                        runID: id
                    )
                }
            }
        )

        notificationTokens.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] notification in
                let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                guard raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else {
                    return
                }
                Task { @MainActor [weak self] in
                    await self?.interrupt(
                        "The microphone disconnected. Choose an input and start again.",
                        runID: id
                    )
                }
            }
        )

        notificationTokens.append(
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.audioServicesWereReset(
                        "Audio services restarted. Start transcription again.",
                        runID: id
                    )
                }
            }
        )

        notificationTokens.append(
            center.addObserver(
                forName: NSNotification.Name.AVAudioEngineConfigurationChange,
                object: audioEngine,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.audioEngineConfigurationChanged(runID: id)
                }
            }
        )

        notificationTokens.append(
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.interrupt(
                        "Transcription stopped when Sideleaf moved to the background.",
                        runID: id
                    )
                }
            }
        )
    }

    /// A media-services reset destroys the audio graph. The engine object cannot be used
    /// again, so it is replaced without being sent any further messages.
    private func audioServicesWereReset(_ message: String, runID id: UUID) async {
        audioEngineIsInvalidated = true
        tapInstalled = false
        tapFormat = nil
        guard runID == id else {
            if runID == nil, state != .finalizing {
                rebuildAudioEngineIfNeeded()
            }
            return
        }
        if state == .finalizing {
            if let shutDownTask {
                _ = await shutDownTask.value
            }
            rebuildAudioEngineIfNeeded()
            return
        }
        await interrupt(message, runID: id)
    }

    /// `AVAudioEngineConfigurationChange` is routine. It arrives while the route settles after
    /// the session is activated and again whenever the input format changes. The engine stays
    /// valid, so the tap is reconnected rather than the session ended. Discarding a running
    /// engine here would tear the audio graph down underneath the render thread.
    private func audioEngineConfigurationChanged(runID id: UUID) async {
        guard runID == id, state == .listening, let bridge = audioBridge else { return }
        let currentFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        let formatChanged = tapFormat.map { $0 != currentFormat } ?? true
        // A notification that leaves the engine running on the same input format changed
        // nothing this session depends on.
        guard !audioEngine.isRunning || formatChanged else { return }

        let now = ContinuousClock.now
        if let lastEngineReconnect, now - lastEngineReconnect < Self.engineReconnectWindow {
            engineReconnects += 1
        } else {
            engineReconnects = 1
        }
        lastEngineReconnect = now
        guard engineReconnects <= Self.engineReconnectLimit else {
            await interrupt(
                "The microphone input kept changing. Start transcription again.",
                runID: id
            )
            return
        }

        audioEngine.stop()
        do {
            try startAudioEngine(with: bridge)
        } catch {
            await interrupt(
                "The microphone input changed and could not be reconnected. Start transcription again.",
                runID: id
            )
        }
    }

    private func interrupt(_ message: String, runID id: UUID) async {
        guard runID == id, state != .finalizing else { return }
        state = .finalizing
        status = "Finishing after an interruption…"
        await shutDownWithoutThrowing(runID: id, finalize: true, waitForResultTask: true)
        guard runID == id else { return }
        runID = nil
        volatile = ""
        state = .interrupted
        status = message
        errorMessage = message
    }

    private func handleAudioFailure(_ error: Error, runID id: UUID) async {
        guard runID == id, state == .listening else { return }
        await fail(error, runID: id)
    }

    private func fail(
        _ error: Error,
        runID id: UUID,
        originatingFromResultTask: Bool = false
    ) async {
        guard runID == id, state != .finalizing else { return }
        let message = (error as? LocalizedError)?.errorDescription
            ?? "Live transcription could not continue."
        let shouldFinalize = state == .listening
        state = .finalizing
        status = "Stopping transcription…"
        await shutDownWithoutThrowing(
            runID: id,
            finalize: shouldFinalize,
            waitForResultTask: !originatingFromResultTask
        )
        guard runID == id else { return }
        completeFailure(error, runID: id, message: message)
    }

    private func abandon(runID id: UUID) async {
        guard runID == id, state != .finalizing else { return }
        state = .finalizing
        status = "Stopping transcription…"
        assetDownloadProgress?.cancel()
        await shutDownWithoutThrowing(runID: id, finalize: false, waitForResultTask: true)
        guard runID == id else { return }
        runID = nil
        state = .stopped
        status = "Transcription is stopped."
    }

    private func completeFailure(
        _ error: Error,
        runID id: UUID,
        message providedMessage: String? = nil
    ) {
        guard runID == id else { return }
        let message = providedMessage
            ?? (error as? LocalizedError)?.errorDescription
            ?? "Live transcription could not continue."
        runID = nil
        volatile = ""
        errorMessage = message
        shouldOfferMicrophoneSettings =
            (error as? LiveTranscriptionError)?.isMicrophonePermissionDenied == true
        if (error as? LiveTranscriptionError)?.isUnavailable == true {
            state = .unavailable
        } else {
            state = .failed
        }
        status = message
    }

    private func shutDownWithoutThrowing(
        runID id: UUID,
        finalize: Bool,
        waitForResultTask: Bool
    ) async {
        try? await shutDown(
            runID: id,
            finalize: finalize,
            waitForResultTask: waitForResultTask
        )
    }

    private func shutDown(
        runID id: UUID,
        finalize: Bool,
        waitForResultTask: Bool
    ) async throws {
        if shutDownRunID == id, let shutDownTask {
            let outcome = await shutDownTask.value
            if outcome == .incomplete {
                throw LiveTranscriptionError.shutDownIncomplete
            }
            return
        }

        guard runID == id else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return LiveTranscriptionShutDownOutcome.incomplete }
            return await self.performShutDown(
                runID: id,
                finalize: finalize,
                waitForResultTask: waitForResultTask
            )
        }
        shutDownRunID = id
        shutDownTask = task

        let outcome = await task.value
        if shutDownRunID == id {
            shutDownTask = nil
            shutDownRunID = nil
        }
        if outcome == .incomplete {
            throw LiveTranscriptionError.shutDownIncomplete
        }
    }

    private func performShutDown(
        runID id: UUID,
        finalize: Bool,
        waitForResultTask: Bool
    ) async -> LiveTranscriptionShutDownOutcome {
        var completedCleanly = true
        removeInterruptionObservers()

        if audioEngineIsInvalidated {
            // A media-services reset invalidates the old engine. Replacing it avoids sending
            // stop/remove-tap messages to an orphaned audio graph.
            audioEngine = AVAudioEngine()
            audioEngineIsInvalidated = false
            tapInstalled = false
        } else {
            // Never release a running engine. Drop its tap and stop it first.
            if tapInstalled {
                audioEngine.inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
            audioEngine.stop()
        }
        tapFormat = nil
        audioBridge?.finishCapture()

        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            completedCleanly = false
        }

        if let audioBridge {
            let drained = await audioBridge.finishAndWait(
                timeout: Self.conversionDrainTimeout
            )
            if !drained {
                completedCleanly = false
                audioBridge.cancel()
            }
        }

        if let analyzer {
            let operation = Task { () -> LiveTranscriptionAnalyzerFinishOutcome in
                if !finalize {
                    await analyzer.cancelAndFinishNow()
                    return .completed
                }

                do {
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                    return .completed
                } catch {
                    await analyzer.cancelAndFinishNow()
                    return .failed
                }
            }

            switch await value(of: operation, before: Self.analyzerFinishTimeout) {
            case .value(.completed):
                break
            case .value(.failed):
                completedCleanly = false
            case .timedOut:
                completedCleanly = false
                operation.cancel()
                quarantineAnalyzerCleanup(operation)
            }
        }

        if let resultTask {
            if waitForResultTask {
                switch await value(of: resultTask, before: Self.resultDrainTimeout) {
                case .value:
                    break
                case .timedOut:
                    completedCleanly = false
                    resultTask.cancel()
                }
            } else {
                resultTask.cancel()
            }
        }

        if cleanupQuarantineTask == nil, let locale = ownedReservedLocale {
            let releaseTask = Task {
                await AssetInventory.release(reservedLocale: locale)
            }
            switch await value(
                of: releaseTask,
                before: Self.assetReleaseTimeout
            ) {
            case .value:
                ownedReservedLocale = nil
            case .timedOut:
                completedCleanly = false
                quarantineAssetRelease(releaseTask, locale: locale)
            }
        }

        if runID == id {
            resultTask = nil
            audioBridge = nil
            analyzer = nil
            transcriber = nil
            assetDownloadProgress = nil
        }
        rebuildAudioEngineIfNeeded()
        return completedCleanly ? .completed : .incomplete
    }

    private func quarantineAnalyzerCleanup(
        _ operation: Task<LiveTranscriptionAnalyzerFinishOutcome, Never>
    ) {
        let acknowledgement = Task {
            _ = await operation.value
        }
        beginCleanupQuarantine(
            waitingFor: acknowledgement,
            ownedLocale: ownedReservedLocale,
            releaseLocaleAfterAcknowledgement: true
        )
    }

    private func quarantineAssetRelease(
        _ releaseTask: Task<Bool, Never>,
        locale: Locale
    ) {
        let acknowledgement = Task {
            _ = await releaseTask.value
        }
        beginCleanupQuarantine(
            waitingFor: acknowledgement,
            ownedLocale: locale,
            releaseLocaleAfterAcknowledgement: false
        )
    }

    private func beginCleanupQuarantine(
        waitingFor acknowledgement: Task<Void, Never>,
        ownedLocale locale: Locale?,
        releaseLocaleAfterAcknowledgement: Bool
    ) {
        guard cleanupQuarantineTask == nil else { return }
        let quarantineID = UUID()
        cleanupQuarantineID = quarantineID
        cleanupQuarantineTask = Task { @MainActor [weak self] in
            await acknowledgement.value
            if releaseLocaleAfterAcknowledgement, let locale {
                _ = await AssetInventory.release(reservedLocale: locale)
            }

            guard let self, self.cleanupQuarantineID == quarantineID else { return }
            if self.ownedReservedLocale == locale {
                self.ownedReservedLocale = nil
            }
            self.cleanupQuarantineTask = nil
            self.cleanupQuarantineID = nil
        }
    }

    private func rebuildAudioEngineIfNeeded() {
        guard audioEngineIsInvalidated else { return }
        audioEngine = AVAudioEngine()
        audioEngineIsInvalidated = false
        tapInstalled = false
        tapFormat = nil
    }

    private func removeInterruptionObservers() {
        let center = NotificationCenter.default
        notificationTokens.forEach(center.removeObserver)
        notificationTokens.removeAll()
    }

    private func ensureCurrentRun(_ id: UUID) throws {
        try Task.checkCancellation()
        guard runID == id, state != .finalizing else { throw CancellationError() }
    }
}

private enum LiveTranscriberSelection: Sendable {
    case speech(SpeechTranscriber, Locale)
    case dictation(DictationTranscriber, Locale)

    var locale: Locale {
        switch self {
        case .speech(_, let locale), .dictation(_, let locale):
            locale
        }
    }

    var module: any SpeechModule {
        switch self {
        case .speech(let transcriber, _):
            transcriber
        case .dictation(let transcriber, _):
            transcriber
        }
    }
}

private enum LiveTranscriptionShutDownOutcome: Sendable {
    case completed
    case incomplete
}

private enum LiveTranscriptionAnalyzerFinishOutcome: Sendable {
    case completed
    case failed
}

private enum TimedTaskValue<Value: Sendable>: Sendable {
    case value(Value)
    case timedOut
}

private func value<Value: Sendable>(
    of task: Task<Value, Never>,
    before timeout: Duration
) async -> TimedTaskValue<Value> {
    let (events, continuation) = AsyncStream<TimedTaskValue<Value>>.makeStream(
        bufferingPolicy: .bufferingNewest(1)
    )
    let waiter = Task.detached {
        let result = await task.value
        guard !Task.isCancelled else { return }
        continuation.yield(.value(result))
    }
    let timer = Task.detached {
        do {
            try await Task.sleep(for: timeout)
        } catch {
            return
        }
        continuation.yield(.timedOut)
    }

    var iterator = events.makeAsyncIterator()
    let first = await iterator.next() ?? .timedOut
    continuation.finish()
    waiter.cancel()
    timer.cancel()
    return first
}

private enum LiveTranscriptionError: LocalizedError {
    case transcriberUnavailable
    case localeUnsupported
    case assetInstallationFailed
    case microphoneDenied
    case noCompatibleAudioFormat
    case noAudioInput
    case audioBufferAllocationFailed
    case audioConversionFailed
    case audioBufferOverrun
    case recognitionFailed
    case shutDownIncomplete

    var isUnavailable: Bool {
        switch self {
        case .transcriberUnavailable, .localeUnsupported:
            true
        default:
            false
        }
    }

    var isMicrophonePermissionDenied: Bool {
        if case .microphoneDenied = self {
            true
        } else {
            false
        }
    }

    var errorDescription: String? {
        switch self {
        case .transcriberUnavailable:
            "On-device transcription is unavailable on this device."
        case .localeUnsupported:
            "On-device transcription is unavailable for this language."
        case .assetInstallationFailed:
            "The on-device language assets could not be installed. Check your connection and try again."
        case .microphoneDenied:
            "Microphone access is off. Allow Sideleaf access in Settings, then try again."
        case .noCompatibleAudioFormat:
            "The device could not prepare a compatible transcription audio format."
        case .noAudioInput:
            "No usable microphone input is available."
        case .audioBufferAllocationFailed:
            "The device could not prepare microphone buffers for transcription."
        case .audioConversionFailed:
            "Microphone audio could not be prepared for transcription."
        case .audioBufferOverrun:
            "Transcription could not keep up with the microphone. The session was stopped without saving audio."
        case .recognitionFailed:
            "On-device speech recognition stopped unexpectedly."
        case .shutDownIncomplete:
            "Transcription stopped, but the final words could not be finalized."
        }
    }
}

/// Keeps the AVAudioEngine callback small, then converts on a bounded background pipeline.
private final class LiveAudioInputBridge: @unchecked Sendable {
    let analyzerInputs: AsyncStream<AnalyzerInput>

    private let capturedContinuation: AsyncStream<CapturedAudioBuffer>.Continuation
    private let analyzerContinuation: AsyncStream<AnalyzerInput>.Continuation
    private let onFailure: @Sendable (Error) -> Void
    private let workerTask: Task<Void, Never>
    /// Guarded because `prepareCapture` can swap the pool from the main actor while the render
    /// thread is reading it during a reconnect.
    private let capturePool = OSAllocatedUnfairLock<LiveAudioBufferPool?>(uncheckedState: nil)

    init(
        outputFormat: AVAudioFormat,
        bufferLimit: Int,
        onFailure: @escaping @Sendable (Error) -> Void
    ) {
        let (capturedInputs, capturedContinuation) = AsyncStream<CapturedAudioBuffer>.makeStream(
            bufferingPolicy: .bufferingNewest(bufferLimit)
        )
        let (analyzerInputs, analyzerContinuation) = AsyncStream<AnalyzerInput>.makeStream(
            bufferingPolicy: .bufferingNewest(bufferLimit)
        )

        self.analyzerInputs = analyzerInputs
        self.capturedContinuation = capturedContinuation
        self.analyzerContinuation = analyzerContinuation
        self.onFailure = onFailure
        let outputFormat = LiveAudioFormatBox(outputFormat)
        workerTask = Task.detached(priority: .userInitiated) {
            let converter = LiveAudioBufferConverter(outputFormat: outputFormat.value)
            defer { analyzerContinuation.finish() }

            do {
                for await captured in capturedInputs {
                    let converted: AVAudioPCMBuffer?
                    do {
                        try Task.checkCancellation()
                        converted = try converter.convert(captured.buffer)
                    } catch {
                        captured.recycle()
                        throw error
                    }
                    captured.recycle()
                    try Task.checkCancellation()
                    guard let converted else { continue }
                    try Self.yield(
                        AnalyzerInput(buffer: converted),
                        to: analyzerContinuation
                    )
                }

                if let tail = try converter.flush() {
                    try Self.yield(AnalyzerInput(buffer: tail), to: analyzerContinuation)
                }
            } catch is CancellationError {
                return
            } catch {
                capturedContinuation.finish()
                onFailure(error)
            }
        }
    }

    func prepareCapture(
        format: AVAudioFormat,
        frameCapacity: AVAudioFrameCount,
        bufferCount: Int
    ) throws {
        guard let pool = LiveAudioBufferPool(
            format: format,
            frameCapacity: frameCapacity,
            bufferCount: bufferCount
        ) else {
            throw LiveTranscriptionError.audioBufferAllocationFailed
        }
        capturePool.withLockUnchecked { $0 = pool }
    }

    func receive(_ buffer: AVAudioPCMBuffer) {
        // The audio callback must never wait for the pool reference. A single missed buffer is
        // preferable to blocking the render thread.
        let lookup = capturePool.withLockIfAvailableUnchecked { pool -> LiveAudioBufferPool? in
            pool
        }
        guard let currentPool = lookup else { return }
        guard let pool = currentPool else {
            capturedContinuation.finish()
            onFailure(LiveTranscriptionError.audioBufferOverrun)
            return
        }
        let captured: CapturedAudioBuffer
        switch pool.copy(buffer) {
        case .captured(let buffer):
            captured = buffer
        case .temporarilyUnavailable:
            // The audio callback must never wait for the worker's pool lock. A
            // single missed buffer is preferable to aborting a healthy session.
            return
        case .invalidBuffer:
            capturedContinuation.finish()
            onFailure(LiveTranscriptionError.audioConversionFailed)
            return
        }

        switch capturedContinuation.yield(captured) {
        case .enqueued:
            break
        case .terminated:
            captured.recycle()
        case .dropped(let dropped):
            dropped.recycle()
            capturedContinuation.finish()
            onFailure(LiveTranscriptionError.audioBufferOverrun)
        @unknown default:
            capturedContinuation.finish()
            onFailure(LiveTranscriptionError.audioBufferOverrun)
        }
    }

    func finishCapture() {
        capturedContinuation.finish()
    }

    func finishAndWait(timeout: Duration) async -> Bool {
        finishCapture()
        switch await value(of: workerTask, before: timeout) {
        case .value:
            return true
        case .timedOut:
            return false
        }
    }

    func cancel() {
        capturedContinuation.finish()
        workerTask.cancel()
        analyzerContinuation.finish()
    }

    private static func yield(
        _ input: AnalyzerInput,
        to continuation: AsyncStream<AnalyzerInput>.Continuation
    ) throws {
        switch continuation.yield(input) {
        case .enqueued:
            break
        case .dropped:
            throw LiveTranscriptionError.audioBufferOverrun
        case .terminated:
            throw CancellationError()
        @unknown default:
            throw LiveTranscriptionError.audioBufferOverrun
        }
    }
}

private struct CapturedAudioBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let pool: LiveAudioBufferPool

    func recycle() {
        pool.recycle(buffer)
    }
}

private enum LiveAudioBufferCapture {
    case captured(CapturedAudioBuffer)
    case temporarilyUnavailable
    case invalidBuffer
}

/// A fixed-size pool keeps AVAudioEngine's real-time tap free of heap allocation and ensures
/// buffers handed to the background converter are independent of AVAudioEngine's storage.
private final class LiveAudioBufferPool: @unchecked Sendable {
    private let available: OSAllocatedUnfairLock<[AVAudioPCMBuffer]>

    init?(
        format: AVAudioFormat,
        frameCapacity: AVAudioFrameCount,
        bufferCount: Int
    ) {
        guard frameCapacity > 0, bufferCount > 0 else { return nil }
        var buffers: [AVAudioPCMBuffer] = []
        buffers.reserveCapacity(bufferCount)
        for _ in 0..<bufferCount {
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCapacity
            ) else {
                return nil
            }
            buffers.append(buffer)
        }
        available = OSAllocatedUnfairLock(uncheckedState: buffers)
    }

    func copy(_ source: AVAudioPCMBuffer) -> LiveAudioBufferCapture {
        available.withLockIfAvailableUnchecked { buffers -> LiveAudioBufferCapture in
            guard let target = buffers.popLast() else { return .temporarilyUnavailable }
            guard copyPCMFrames(from: source, to: target) else {
                buffers.append(target)
                return .invalidBuffer
            }
            return .captured(CapturedAudioBuffer(buffer: target, pool: self))
        } ?? .temporarilyUnavailable
    }

    func recycle(_ buffer: AVAudioPCMBuffer) {
        buffer.frameLength = 0
        available.withLockUnchecked { buffers in
            buffers.append(buffer)
        }
    }
}

private final class LiveAudioFormatBox: @unchecked Sendable {
    let value: AVAudioFormat

    init(_ value: AVAudioFormat) {
        self.value = value
    }
}

private func copyPCMFrames(
    from source: AVAudioPCMBuffer,
    to destination: AVAudioPCMBuffer
) -> Bool {
    guard source.format == destination.format,
          source.frameLength <= destination.frameCapacity else {
        return false
    }

    destination.frameLength = source.frameLength
    let sourceBuffers = UnsafeMutableAudioBufferListPointer(
        UnsafeMutablePointer(mutating: source.audioBufferList)
    )
    let destinationBuffers = UnsafeMutableAudioBufferListPointer(
        destination.mutableAudioBufferList
    )
    guard sourceBuffers.count == destinationBuffers.count else {
        destination.frameLength = 0
        return false
    }

    for index in sourceBuffers.indices {
        let sourceBuffer = sourceBuffers[index]
        let destinationBuffer = destinationBuffers[index]
        guard sourceBuffer.mNumberChannels == destinationBuffer.mNumberChannels,
              sourceBuffer.mDataByteSize <= destinationBuffer.mDataByteSize else {
            destination.frameLength = 0
            return false
        }
        guard sourceBuffer.mDataByteSize > 0 else { continue }
        guard let sourceData = sourceBuffer.mData,
              let destinationData = destinationBuffer.mData else {
            destination.frameLength = 0
            return false
        }
        destinationData.copyMemory(
            from: sourceData,
            byteCount: Int(sourceBuffer.mDataByteSize)
        )
    }
    return true
}

private final class LiveAudioBufferConverter {
    private let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?

    init(outputFormat: AVAudioFormat) {
        self.outputFormat = outputFormat
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer? {
        if buffer.format == outputFormat {
            guard let copied = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: max(1, buffer.frameLength)
            ), copyPCMFrames(from: buffer, to: copied) else {
                throw LiveTranscriptionError.audioConversionFailed
            }
            return copied.frameLength == 0 ? nil : copied
        }

        if converter == nil
            || converterInputFormat != buffer.format
            || converter?.outputFormat != outputFormat {
            converter = AVAudioConverter(from: buffer.format, to: outputFormat)
            converter?.primeMethod = .none
            converterInputFormat = buffer.format
        }
        guard let converter else { throw LiveTranscriptionError.audioConversionFailed }

        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount(
            max(1, (Double(buffer.frameLength) * ratio).rounded(.up) + 32)
        )
        guard let converted = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: capacity
        ) else {
            throw LiveTranscriptionError.audioConversionFailed
        }

        var conversionError: NSError?
        let input = SingleAudioBufferSource(buffer)
        let conversionStatus = converter.convert(to: converted, error: &conversionError) {
            _, inputStatus in
            input.next(status: inputStatus)
        }
        guard conversionStatus != .error else {
            throw conversionError ?? LiveTranscriptionError.audioConversionFailed
        }
        return converted.frameLength == 0 ? nil : converted
    }

    func flush() throws -> AVAudioPCMBuffer? {
        guard let converter else { return nil }
        let capacity = AVAudioFrameCount(max(1, converter.outputFormat.sampleRate / 10))
        guard let converted = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: capacity
        ) else {
            throw LiveTranscriptionError.audioConversionFailed
        }

        var conversionError: NSError?
        let conversionStatus = converter.convert(to: converted, error: &conversionError) {
            _, inputStatus in
            inputStatus.pointee = .endOfStream
            return nil
        }
        guard conversionStatus != .error else {
            throw conversionError ?? LiveTranscriptionError.audioConversionFailed
        }
        return converted.frameLength == 0 ? nil : converted
    }
}

private final class SingleAudioBufferSource: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private var supplied = false

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(
        status: UnsafeMutablePointer<AVAudioConverterInputStatus>
    ) -> AVAudioBuffer? {
        guard !supplied else {
            status.pointee = .noDataNow
            return nil
        }
        supplied = true
        status.pointee = .haveData
        return buffer
    }
}
