import Foundation

/// What Sideleaf has learned about which suggestions this person wants.
///
/// It is a tally, not a model: how often each kind of suggestion was kept or
/// dismissed. A kind that has been dismissed repeatedly and never kept stops
/// being offered, and the meeting screen says so with a control to bring it
/// back. Nothing here is hidden from the person and nothing leaves the device.
struct MeetingCuePreferences: Codable, Equatable, Sendable {
    struct Record: Codable, Equatable, Sendable {
        var kept = 0
        var dismissed = 0
    }

    /// Lifetime dismissals of one kind, with nothing ever kept, before Sideleaf
    /// stops offering it.
    static let muteThreshold = 6

    var records: [String: Record] = [:]

    var mutedKinds: Set<MeetingCue.Kind> {
        var muted: Set<MeetingCue.Kind> = []
        for (rawValue, record) in records {
            guard let kind = MeetingCue.Kind(rawValue: rawValue) else { continue }
            if record.kept == 0, record.dismissed >= Self.muteThreshold { muted.insert(kind) }
        }
        return muted
    }

    mutating func record(_ feedback: MeetingCueFeedback) {
        // Notes are written by the person, so they teach nothing about what
        // Sideleaf should suggest.
        guard feedback.kind != .note else { return }
        var record = records[feedback.kind.rawValue] ?? Record()
        switch feedback.action {
        case .dismissed: record.dismissed += 1
        case .kept, .asked: record.kept += 1
        case .open, .resolved: return
        }
        records[feedback.kind.rawValue] = record
    }

    /// Brings a kind back and clears the run of dismissals that silenced it.
    mutating func unmute(_ kind: MeetingCue.Kind) {
        records[kind.rawValue] = Record()
    }

    mutating func forgetEverything() {
        records = [:]
    }
}

/// Keeps the tally beside the meeting snapshot, in the shared container.
enum MeetingPreferencesStore {
    private static let key = "meeting.cue.preferences"

    static func load() -> MeetingCuePreferences {
        guard let data = MeetingSharedStore.defaults.data(forKey: key),
              let preferences = try? JSONDecoder().decode(MeetingCuePreferences.self, from: data)
        else { return MeetingCuePreferences() }
        return preferences
    }

    static func save(_ preferences: MeetingCuePreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        MeetingSharedStore.defaults.set(data, forKey: key)
    }
}
