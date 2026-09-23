import AVFoundation
import FluidAudio
import Foundation
import Observation
import os

/// The only file that knows which speech library Sideleaf uses.
///
/// Written against FluidAudio's documented streaming API:
///
///     let diarizer = SortformerDiarizer()
///     let models = try await SortformerModels.loadFromHuggingFace(config: .default)
///     diarizer.initialize(models: models)
///     try diarizer.addAudio(chunk, sourceSampleRate: 16_000)
///     if let update = try diarizer.process() { update.finalizedSegments }
///     try diarizer.enrollSpeaker(withAudio: chunk, named: "You",
///                                overwritingAssignedSpeakerName: nil)
///
/// Sortformer is the right shape for a meeting: four stable speaker slots, so
/// identities hold across a conversation instead of being renumbered.
/// If any of those signatures have moved, this file is the only one to fix.
/// https://github.com/FluidInference/FluidAudio
@MainActor
@Observable
final class FluidAudioSpeakerRecognizer: SpeakerRecognizing {
    /// A stretch of meeting time that belonged to one voice.
    struct SpeakerSpan: Equatable, Sendable {
        var start: TimeInterval
        var end: TimeInterval
        var identifier: String

        var isYou: Bool { identifier == VoiceProfile.speakerName }
    }

    /// Below this much attributed speech in a window, Sideleaf says nothing.
    static let minimumAttributedSeconds: TimeInterval = 0.6
    /// How much of a window one voice must hold to own it.
    static let dominantShare: Double = 0.7
    /// How often buffered audio is handed to the model.
    static let drainInterval = Duration.milliseconds(900)

    private(set) var state: VoiceRecognizerState = .idle
    private(set) var profile: VoiceProfile?
    /// Names or identifiers heard in the current meeting. Shown in settings so
    /// it is obvious whether attribution is actually working.
    private(set) var heardSpeakers: [String] = []

    @ObservationIgnored private let engine = DiarizationEngine()
    @ObservationIgnored private var drainTask: Task<Void, Never>?
    @ObservationIgnored private var spans: [String: SpeakerSpan] = [:]
    @ObservationIgnored private let log = Logger(
        subsystem: "com.thinkhale.sideleaf",
        category: "voice"
    )

    /// One recogniser for the app: settings enrols into the same instance the
    /// meeting listens with.
    static let shared = FluidAudioSpeakerRecognizer()

    init() {
        profile = VoiceProfileStore.profile()
    }

    // MARK: - Lifecycle

    func prepare() async {
        guard state != .preparing, !state.isReady else { return }
        state = .preparing
        do {
            try await engine.load()
            if let samples = VoiceProfileStore.samples(), !samples.isEmpty {
                try await engine.enroll(samples)
            }
            state = .ready
        } catch {
            log.error("voice models unavailable: \(error.localizedDescription, privacy: .public)")
            state = .unavailable(error.localizedDescription)
        }
    }

    func enroll(
        samples: [Float],
        sampleRate: Double
    ) async -> Result<VoiceProfile, VoiceEnrollmentFailure> {
        let seconds = sampleRate > 0 ? Double(samples.count) / sampleRate : 0
        guard seconds >= VoiceProfile.minimumSeconds else {
            return .failure(.tooShort(seconds))
        }
        let resampled = VoiceAudioResampler.convert(
            samples,
            from: sampleRate,
            to: DiarizationEngine.modelSampleRate
        )
        guard !resampled.isEmpty else {
            return .failure(.failed("The recording could not be prepared for the model."))
        }
        await prepare()
        guard state.isReady else {
            guard case .unavailable(let reason) = state else {
                return .failure(.modelsUnavailable("Try again in a moment."))
            }
            return .failure(.modelsUnavailable(reason))
        }
        do {
            try await engine.enroll(resampled)
            let stored = try VoiceProfileStore.save(
                samples: resampled,
                sampleRate: DiarizationEngine.modelSampleRate
            )
            profile = stored
            return .success(stored)
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
    }

    func forget() {
        VoiceProfileStore.delete()
        profile = nil
        spans = [:]
        heardSpeakers = []
        Task { await engine.reset() }
    }

    // MARK: - Meetings

    func beginMeeting(sink: VoiceAudioSink) async {
        spans = [:]
        heardSpeakers = []
        guard profile != nil else { return }
        await prepare()
        guard state.isReady else { return }
        await engine.beginMeeting()
        drainTask?.cancel()
        drainTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: FluidAudioSpeakerRecognizer.drainInterval)
                guard !Task.isCancelled, let self else { return }
                await self.consume(from: sink)
            }
        }
    }

    func endMeeting() {
        drainTask?.cancel()
        drainTask = nil
        Task { await engine.endMeeting() }
    }

    func speaker(during window: ClosedRange<TimeInterval>) -> MeetingSpeaker {
        guard profile != nil, state.isReady else { return .unknown }
        var yours: TimeInterval = 0
        var theirs: TimeInterval = 0
        for span in spans.values {
            let overlap = min(span.end, window.upperBound) - max(span.start, window.lowerBound)
            guard overlap > 0 else { continue }
            if span.isYou { yours += overlap } else { theirs += overlap }
        }
        let total = yours + theirs
        guard total >= Self.minimumAttributedSeconds else { return .unknown }
        if yours / total >= Self.dominantShare { return .you }
        if theirs / total >= Self.dominantShare { return .other }
        // Two people talking over each other is not an attribution.
        return .unknown
    }

    private func consume(from sink: VoiceAudioSink) async {
        let captured = sink.drain()
        guard !captured.samples.isEmpty, captured.sampleRate > 0 else { return }
        do {
            let fresh = try await engine.add(
                captured.samples,
                sampleRate: captured.sampleRate
            )
            guard !fresh.isEmpty else { return }
            for span in fresh {
                spans["\(span.identifier)@\(span.start)"] = span
            }
            let names = Set(spans.values.map(\.identifier)).sorted()
            if names != heardSpeakers { heardSpeakers = names }
        } catch {
            log.error("voice attribution stopped: \(error.localizedDescription, privacy: .public)")
            drainTask?.cancel()
            drainTask = nil
            state = .unavailable(error.localizedDescription)
        }
    }
}

/// Owns the model. Inference never runs on the main actor, and the library's
/// own types never leave this actor.
private actor DiarizationEngine {
    /// Sortformer's input rate.
    static let modelSampleRate: Double = 16_000

    private var diarizer: SortformerDiarizer?

    func load() async throws {
        guard diarizer == nil else { return }
        let models = try await SortformerModels.loadFromHuggingFace(config: .default)
        let diarizer = SortformerDiarizer()
        diarizer.initialize(models: models)
        self.diarizer = diarizer
    }

    func enroll(_ samples: [Float]) throws {
        guard let diarizer else { throw VoiceEnrollmentFailure.modelsUnavailable("No model loaded.") }
        try diarizer.enrollSpeaker(
            withAudio: samples,
            named: VoiceProfile.speakerName,
            overwritingAssignedSpeakerName: nil
        )
    }

    func beginMeeting() {}

    func endMeeting() {}

    func reset() {
        diarizer = nil
    }

    /// Hands new audio to the model and returns whatever it has now finalised.
    func add(
        _ samples: [Float],
        sampleRate: Double
    ) throws -> [FluidAudioSpeakerRecognizer.SpeakerSpan] {
        guard let diarizer else { return [] }
        try diarizer.addAudio(samples, sourceSampleRate: Int(sampleRate.rounded()))
        guard let update = try diarizer.process() else { return [] }
        return update.finalizedSegments.map { segment in
            FluidAudioSpeakerRecognizer.SpeakerSpan(
                start: TimeInterval(segment.startTimeSeconds),
                end: TimeInterval(segment.endTimeSeconds),
                // The library names enrolled speakers and numbers the rest.
                // Whatever it returns is compared against the name Sideleaf
                // enrolled you under.
                identifier: String(describing: segment.speakerId)
            )
        }
    }
}
