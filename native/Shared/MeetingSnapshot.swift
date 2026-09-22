import Foundation

/// The small, shareable picture of what Sideleaf is doing right now.
///
/// The app owns it. The Home Screen widget reads it from the shared App Group
/// container, and the Apple Watch app receives a copy over WatchConnectivity.
/// It holds only what those surfaces draw, never the transcript.
struct MeetingSnapshot: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        case idle
        case starting
        case live
        case finishing
        case ended
        case unavailable
    }

    var phase: Phase
    var kind: MeetingKind
    var title: String
    var startedAt: Date?
    var endedAt: Date?
    /// A short human status line, mirrored from the transcription controller.
    var status: String
    var openAskCount: Int
    var rememberCount: Int
    /// The few cues a widget or watch face can actually show.
    var topCues: [MeetingCue]
    /// Plan points that have not been covered yet.
    var planRemaining: [String]
    var updatedAt: Date

    static let cueLimit = 3

    static let idle = MeetingSnapshot(
        phase: .idle,
        kind: .meeting,
        title: "",
        startedAt: nil,
        endedAt: nil,
        status: "Ready when you are.",
        openAskCount: 0,
        rememberCount: 0,
        topCues: [],
        planRemaining: [],
        updatedAt: Date(timeIntervalSince1970: 0)
    )

    var isLive: Bool { phase == .live || phase == .starting || phase == .finishing }

    /// How long a live snapshot is trusted without a fresh write. A meeting
    /// that stopped without cleaning up should not leave a widget counting
    /// forever.
    static let freshness: TimeInterval = 900

    func showsLiveMeeting(now: Date = Date()) -> Bool {
        isLive && now.timeIntervalSince(updatedAt) < Self.freshness
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.defaultTitle : trimmed
    }

    /// Keeps the snapshot small enough for a WatchConnectivity context.
    func bounded() -> MeetingSnapshot {
        var copy = self
        copy.topCues = Array(topCues.prefix(Self.cueLimit)).map { cue in
            var trimmed = cue
            trimmed.prompt = String(cue.prompt.prefix(220))
            trimmed.quote = String(cue.quote.prefix(220))
            return trimmed
        }
        copy.planRemaining = Array(planRemaining.prefix(4)).map { String($0.prefix(80)) }
        copy.title = String(title.prefix(120))
        copy.status = String(status.prefix(160))
        return copy
    }
}

/// A start or stop asked for from outside the app: a widget button, a control,
/// or the watch. The app consumes it when it next becomes active.
struct MeetingRequest: Codable, Equatable, Sendable {
    enum Action: String, Codable, Sendable {
        case start
        case stop
        case open
        /// Keep this moment, from the wrist.
        case markMoment
        /// A suggested question was asked out loud.
        case markAsked
    }

    var action: Action
    var kind: MeetingKind?
    /// The cue a `markAsked` request refers to.
    var cueID: UUID?
    var requestedAt: Date

    init(
        action: Action,
        kind: MeetingKind? = nil,
        cueID: UUID? = nil,
        requestedAt: Date = Date()
    ) {
        self.action = action
        self.kind = kind
        self.cueID = cueID
        self.requestedAt = requestedAt
    }

    /// Requests go stale rather than starting a microphone long after the tap.
    func isFresh(now: Date = Date(), window: TimeInterval = 180) -> Bool {
        now.timeIntervalSince(requestedAt) <= window && now >= requestedAt.addingTimeInterval(-60)
    }
}

/// Shared storage for the snapshot and for pending requests.
///
/// Every accessor degrades to a private container when the App Group
/// entitlement is missing, so a build without the capability still runs; the
/// widget then shows its idle face instead of live meeting state.
enum MeetingSharedStore {
    static let appGroup = "group.com.thinkhale.sideleaf"

    private static let snapshotKey = "meeting.snapshot"
    private static let requestKey = "meeting.request"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func loadSnapshot() -> MeetingSnapshot {
        decode(MeetingSnapshot.self, key: snapshotKey) ?? .idle
    }

    static func save(_ snapshot: MeetingSnapshot) {
        encode(snapshot.bounded(), key: snapshotKey)
    }

    static func clearSnapshot() {
        defaults.removeObject(forKey: snapshotKey)
    }

    static func submit(_ request: MeetingRequest) {
        encode(request, key: requestKey)
        // When the intent runs inside the app, the app is already foreground and
        // would otherwise not look again until the next activation.
        NotificationCenter.default.post(name: .sideleafMeetingRequest, object: nil)
    }

    /// Reads and removes a pending request so one tap cannot start two meetings.
    static func takeRequest(now: Date = Date()) -> MeetingRequest? {
        guard let request = decode(MeetingRequest.self, key: requestKey) else { return nil }
        defaults.removeObject(forKey: requestKey)
        return request.isFresh(now: now) ? request : nil
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<Value: Encodable>(_ value: Value, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}

extension Notification.Name {
    /// Posted in whichever process submitted a meeting request.
    static let sideleafMeetingRequest = Notification.Name("com.thinkhale.sideleaf.meeting-request")
}
