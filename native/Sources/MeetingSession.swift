import Foundation
import Observation
import UIKit
import WidgetKit

/// One meeting, from the moment the person starts listening to the moment they
/// decide what to keep.
///
/// The session owns the live cue list, the elapsed clock and the picture of
/// itself that the Home Screen widget and the Apple Watch app read. It does not
/// own storage: the recap is handed to `NotebookSync` only when the person
/// saves it.
@MainActor
@Observable
final class MeetingSession {
    enum Phase: Equatable, Sendable {
        case idle
        case preparing
        case live
        case finishing
        case ended
    }

    private(set) var phase: Phase = .idle
    private(set) var plan = MeetingPlan()
    private(set) var cues: [MeetingCue] = []
    private(set) var startedAt: Date?
    private(set) var endedAt: Date?
    /// The page this meeting was started from, when it was started from one.
    private(set) var attachedPageID: UUID?
    /// Set when the newest cue has not been seen yet, so the live view can
    /// announce it and the watch can tap the wrist.
    private(set) var latestCueID: UUID?
    private(set) var interruptionNotice: String?
    /// Why the last attempt to start never reached the microphone.
    private(set) var startFailure: String?
    /// Who Sideleaf believes has been talking in the text it is about to read.
    /// Nothing sets this until a voice profile exists, so it stays `unknown`
    /// and cues fall back to assuming the phone's owner is speaking.
    var currentSpeaker: MeetingSpeaker = .unknown

    let transcription: LiveTranscription
    /// Tells your voice from the room's, when a profile has been recorded.
    let recognizer: any SpeakerRecognizing

    @ObservationIgnored private var engine = MeetingCueEngine()
    @ObservationIgnored private var preferences = MeetingPreferencesStore.load()
    /// Kinds Sideleaf has stopped offering, and why the home screen says so.
    private(set) var mutedKinds: [MeetingCue.Kind] = []
    @ObservationIgnored private var pulseTask: Task<Void, Never>?
    @ObservationIgnored private var lastWidgetPublish = Date.distantPast
    @ObservationIgnored private let voiceSink = VoiceAudioSink()
    /// Where the previous pass through the transcript stopped, so attribution
    /// can be asked about exactly the stretch of speech that produced it.
    @ObservationIgnored private var lastPulseElapsed: TimeInterval = 0
    @ObservationIgnored private var publish: (MeetingSnapshot) -> Void

    /// How often the session reads new transcript text. Fast enough to feel
    /// live, slow enough to leave the transcriber alone.
    static let pulseInterval = Duration.milliseconds(1_200)
    /// The widget timeline is reloaded no more often than this while listening.
    static let widgetPublishInterval: TimeInterval = 20
    /// Roughly how far behind the room the finalised transcript runs. Speech is
    /// attributed to the stretch of audio that produced it, not to the moment
    /// its text arrived.
    static let transcriptLag: TimeInterval = 1.5

    init(
        transcription: LiveTranscription = LiveTranscription(),
        recognizer: any SpeakerRecognizing = FluidAudioSpeakerRecognizer.shared,
        publish: @escaping (MeetingSnapshot) -> Void = { _ in }
    ) {
        self.transcription = transcription
        self.recognizer = recognizer
        self.publish = publish
        engine = MeetingCueEngine(mutedKinds: preferences.mutedKinds)
        mutedKinds = engine.mutedKinds.sorted { $0.rawValue < $1.rawValue }
    }

    /// Lets the app send every snapshot on to the Apple Watch without the
    /// session knowing anything about connectivity.
    func publishTo(_ publish: @escaping (MeetingSnapshot) -> Void) {
        self.publish = publish
    }

    // MARK: - Derived state

    var isActive: Bool { phase == .preparing || phase == .live || phase == .finishing }
    var isListening: Bool { transcription.isListening }
    var hasRecap: Bool { phase == .ended && startedAt != nil }

    var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        return (endedAt ?? Date()).timeIntervalSince(startedAt)
    }

    var transcript: String { transcription.transcript }

    var status: String {
        if let interruptionNotice { return interruptionNotice }
        return transcription.status
    }

    var errorMessage: String? { transcription.errorMessage }

    var shouldOfferMicrophoneSettings: Bool { transcription.shouldOfferMicrophoneSettings }

    func clearStartFailure() {
        startFailure = nil
    }

    /// Open questions, most useful first, for the live view and the watch.
    var liveAsks: [MeetingCue] {
        cues
            .filter { $0.role == .ask && $0.isOpen }
            .sorted { left, right in
                left.priority == right.priority
                    ? left.offset > right.offset
                    : left.priority > right.priority
            }
    }

    /// Suggestions the conversation itself answered while the person listened.
    var answeredDuringMeeting: [MeetingCue] {
        cues.filter { $0.state == .resolved }.sorted { $0.offset > $1.offset }
    }

    /// Things to remember, newest first.
    var captured: [MeetingCue] {
        cues.filter { $0.role == .remember && $0.state != .dismissed }
            .sorted { $0.offset > $1.offset }
    }

    var openAskCount: Int { liveAsks.count }

    var planPoints: [MeetingPlanPoint] { engine.planPoints }

    // MARK: - Lifecycle

    func start(plan: MeetingPlan, attachedTo pageID: UUID? = nil) async {
        // A finished meeting waiting to be saved is never replaced silently.
        guard !isActive, phase != .ended else { return }
        self.plan = plan
        attachedPageID = pageID
        preferences = MeetingPreferencesStore.load()
        engine = MeetingCueEngine(plan: plan, mutedKinds: preferences.mutedKinds)
        mutedKinds = engine.mutedKinds.sorted { $0.rawValue < $1.rawValue }
        cues = []
        latestCueID = nil
        interruptionNotice = nil
        startFailure = nil
        endedAt = nil
        startedAt = Date()
        lastPulseElapsed = 0
        currentSpeaker = .unknown
        phase = .preparing
        publishSnapshot(force: true)
        beginVoiceAttribution()
        beginPulse()
        await transcription.start(clearTranscript: true)
        if !transcription.isListening, didFailToStart {
            abandonStart()
            return
        }
        phase = transcription.isListening ? .live : .preparing
        publishSnapshot(force: true)
    }

    /// Hands the transcriber a second reader of the microphone, but only when a
    /// voice profile exists. With no profile nothing is attached and the
    /// capture path is byte for byte what it was.
    private func beginVoiceAttribution() {
        voiceSink.reset()
        guard recognizer.profile != nil else {
            transcription.attachVoiceSink(nil)
            return
        }
        transcription.attachVoiceSink(voiceSink)
        Task { await recognizer.beginMeeting(sink: voiceSink) }
    }

    private func endVoiceAttribution() {
        recognizer.endMeeting()
        transcription.attachVoiceSink(nil)
        voiceSink.reset()
        currentSpeaker = .unknown
    }

    private var didFailToStart: Bool {
        transcription.errorMessage != nil
            || transcription.state == .failed
            || transcription.state == .unavailable
    }

    /// Returns to the home screen with the reason, rather than handing the
    /// person an empty recap for a meeting that never started.
    private func abandonStart() {
        pulseTask?.cancel()
        pulseTask = nil
        endVoiceAttribution()
        startFailure = transcription.errorMessage
            ?? "Sideleaf could not start listening on this device."
        phase = .idle
        startedAt = nil
        endedAt = nil
        cues = []
        publishSnapshot(force: true)
        MeetingSharedStore.clearSnapshot()
        reloadWidgets()
    }

    /// Stops listening and closes the cue list. The recap stays in memory until
    /// the person saves or discards it.
    func finish() async {
        guard phase != .ended, startedAt != nil else { return }
        phase = .finishing
        publishSnapshot(force: true)
        await transcription.stop()
        pulseTask?.cancel()
        pulseTask = nil
        let ended = Date()
        resolveSpeaker(upTo: ended.timeIntervalSince(startedAt ?? ended))
        endedAt = ended
        let closing = engine.finish(
            transcript: transcription.transcript,
            elapsed: ended.timeIntervalSince(startedAt ?? ended),
            now: ended,
            speaker: currentSpeaker
        )
        absorb(closing)
        endVoiceAttribution()
        phase = .ended
        publishSnapshot(force: true)
    }

    /// Clears a finished meeting once it has been saved or deliberately dropped.
    func reset() {
        pulseTask?.cancel()
        pulseTask = nil
        endVoiceAttribution()
        lastPulseElapsed = 0
        phase = .idle
        cues = []
        startedAt = nil
        endedAt = nil
        attachedPageID = nil
        latestCueID = nil
        interruptionNotice = nil
        startFailure = nil
        preferences = MeetingPreferencesStore.load()
        engine = MeetingCueEngine(mutedKinds: preferences.mutedKinds)
        mutedKinds = engine.mutedKinds.sorted { $0.rawValue < $1.rawValue }
        transcription.resetTranscript()
        publishSnapshot(force: true)
        MeetingSharedStore.clearSnapshot()
        reloadWidgets()
    }

    // MARK: - Cue actions

    func markAsked(_ cue: MeetingCue) {
        apply(cue, feedback: .asked) { $0.state = .asked }
    }

    func keep(_ cue: MeetingCue) {
        apply(cue, feedback: .kept) { $0.state = .kept }
    }

    func dismiss(_ cue: MeetingCue) {
        apply(cue, feedback: .dismissed) { $0.state = .dismissed }
    }

    /// Puts a suggestion back, including one Sideleaf decided the room had
    /// already answered.
    func reopen(_ cue: MeetingCue) {
        apply(cue, feedback: nil) {
            $0.state = .open
            $0.resolution = nil
        }
    }

    func edit(_ cue: MeetingCue, prompt: String) {
        apply(cue, feedback: nil) { $0.prompt = prompt }
    }

    func setDueDate(_ date: Date?, for cue: MeetingCue) {
        apply(cue, feedback: nil) { $0.dueDate = date }
    }

    /// Moves a piece of work between you and them. A correction always wins
    /// over whatever Sideleaf decided.
    func setOwner(_ owner: MeetingSpeaker, for cue: MeetingCue) {
        apply(cue, feedback: nil) {
            $0.owner = owner
            $0.ownerSource = .corrected
        }
    }

    /// Work this meeting left with you.
    var yourWork: [MeetingCue] {
        captured.filter { $0.carriesWork && $0.owedBy != .other }
    }

    /// Work the other side left holding.
    var theirWork: [MeetingCue] {
        captured.filter { $0.carriesWork && $0.owedBy == .other }
    }

    /// Starts offering a kind again after Sideleaf stopped.
    func unmute(_ kind: MeetingCue.Kind) {
        engine.unmute(kind)
        preferences.unmute(kind)
        MeetingPreferencesStore.save(preferences)
        mutedKinds = engine.mutedKinds.sorted { $0.rawValue < $1.rawValue }
    }

    /// Clears everything Sideleaf has inferred from past dismissals.
    func forgetSuggestionHistory() {
        preferences.forgetEverything()
        MeetingPreferencesStore.save(preferences)
        for kind in mutedKinds { engine.unmute(kind) }
        mutedKinds = []
    }

    /// Keeps a moment the person noticed before Sideleaf did.
    @discardableResult
    func markMoment(note: String = "") -> MeetingCue {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let cue = MeetingCue(
            kind: .note,
            prompt: trimmed.isEmpty ? "Marked by you" : trimmed,
            quote: recentSpeech(),
            createdAt: Date(),
            offset: elapsed,
            state: .kept,
            priority: 95
        )
        cues.append(cue)
        latestCueID = cue.id
        publishSnapshot(force: true)
        return cue
    }

    func acknowledgeLatestCue() {
        latestCueID = nil
    }

    /// The recap the person reviews, with dismissed cues left out.
    func recapDraft(calendar: Calendar = .current) -> MeetingRecapDraft? {
        guard let startedAt else { return nil }
        return MeetingRecapBuilder.build(
            plan: plan,
            cues: cues,
            startedAt: startedAt,
            endedAt: endedAt ?? Date(),
            calendar: calendar
        )
    }

    // MARK: - Live loop

    private func beginPulse() {
        pulseTask?.cancel()
        pulseTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: MeetingSession.pulseInterval)
                guard !Task.isCancelled, let self else { return }
                self.pulse()
            }
        }
    }

    private func pulse() {
        guard isActive else { return }
        if transcription.isListening, phase == .preparing { phase = .live }
        noticeInterruption()
        resolveSpeaker(upTo: elapsed)
        let changes = engine.ingest(
            transcript: transcription.transcript,
            elapsed: elapsed,
            now: Date(),
            speaker: currentSpeaker
        )
        absorb(changes)
        publishSnapshot(force: !changes.isEmpty)
    }

    /// Asks the recogniser who held the floor during the audio that produced
    /// the text about to be read, allowing for how far the transcript trails
    /// the room.
    private func resolveSpeaker(upTo elapsed: TimeInterval) {
        defer { lastPulseElapsed = elapsed }
        guard recognizer.profile != nil else {
            currentSpeaker = .unknown
            return
        }
        let end = max(0, elapsed - Self.transcriptLag)
        let start = max(0, min(lastPulseElapsed - Self.transcriptLag, end))
        guard end > start else {
            currentSpeaker = .unknown
            return
        }
        currentSpeaker = recognizer.speaker(during: start...end)
    }

    private func noticeInterruption() {
        switch transcription.state {
        case .interrupted:
            interruptionNotice = "Listening paused. Sideleaf will keep your cues."
        case .failed, .unavailable:
            interruptionNotice = transcription.errorMessage
        case .listening:
            interruptionNotice = nil
        default:
            break
        }
    }

    /// Takes what the engine now offers, and what it has changed its mind
    /// about. A revision is silent: nothing new is being asked of the person.
    private func absorb(_ changes: MeetingCueChanges) {
        for revision in changes.revised {
            guard let index = cues.firstIndex(where: { $0.id == revision.id }) else { continue }
            cues[index] = revision
            if revision.state != .open, latestCueID == revision.id { latestCueID = nil }
        }
        guard !changes.created.isEmpty else { return }
        cues.append(contentsOf: changes.created)
        latestCueID = changes.created.last?.id
        if let newest = changes.created.first(where: { $0.role == .ask }) ?? changes.created.last {
            announce(newest)
        }
    }

    private func announce(_ cue: MeetingCue) {
        guard UIApplication.shared.applicationState == .active else { return }
        let generator = UIImpactFeedbackGenerator(style: cue.role == .ask ? .medium : .light)
        generator.impactOccurred()
    }

    private func apply(
        _ cue: MeetingCue,
        feedback: MeetingCue.State?,
        _ change: (inout MeetingCue) -> Void
    ) {
        guard let index = cues.firstIndex(where: { $0.id == cue.id }) else { return }
        change(&cues[index])
        engine.update(cues[index])
        if let feedback {
            let verdict = MeetingCueFeedback(kind: cues[index].kind, action: feedback)
            engine.record(verdict)
            preferences.record(verdict)
            MeetingPreferencesStore.save(preferences)
            mutedKinds = engine.mutedKinds.sorted { $0.rawValue < $1.rawValue }
        }
        if cues[index].state != .open, latestCueID == cue.id { latestCueID = nil }
        publishSnapshot(force: true)
    }

    /// The tail of the transcript, used as the source quote for a manual mark.
    private func recentSpeech(limit: Int = 240) -> String {
        let text = transcription.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > limit else { return text }
        return "…" + String(text.suffix(limit))
    }

    // MARK: - Sharing state

    func snapshot() -> MeetingSnapshot {
        MeetingSnapshot(
            phase: snapshotPhase,
            kind: plan.kind,
            title: plan.displayTitle,
            startedAt: startedAt,
            endedAt: endedAt,
            status: status,
            openAskCount: openAskCount,
            rememberCount: captured.count,
            topCues: Array(liveAsks.prefix(MeetingSnapshot.cueLimit)),
            planRemaining: engine.uncoveredPoints,
            updatedAt: Date()
        )
    }

    private var snapshotPhase: MeetingSnapshot.Phase {
        switch phase {
        case .idle: .idle
        case .preparing: .starting
        case .live: transcription.state == .failed ? .unavailable : .live
        case .finishing: .finishing
        case .ended: .ended
        }
    }

    private func publishSnapshot(force: Bool) {
        let snapshot = snapshot()
        MeetingSharedStore.save(snapshot)
        publish(snapshot)
        let now = Date()
        guard force || now.timeIntervalSince(lastWidgetPublish) >= Self.widgetPublishInterval
        else { return }
        lastWidgetPublish = now
        reloadWidgets()
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
