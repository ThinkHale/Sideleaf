import Foundation

/// The wire format between iPhone and Apple Watch.
///
/// Both sides encode their payload as JSON `Data` before it enters a
/// WatchConnectivity dictionary, so the values that cross a thread boundary are
/// always plain bytes and the decoded types are `Sendable`.
enum WatchMessage {
    static let snapshotKey = "sideleaf.snapshot"
    static let requestKey = "sideleaf.request"
    static let acknowledgementKey = "sideleaf.accepted"

    static func payload(for request: MeetingRequest) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(request) else { return [:] }
        return [requestKey: data]
    }

    static func payload(for snapshot: MeetingSnapshot) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(snapshot.bounded()) else { return [:] }
        return [snapshotKey: data]
    }

    static func request(in message: [String: Any]) -> MeetingRequest? {
        guard let data = message[requestKey] as? Data else { return nil }
        return try? JSONDecoder().decode(MeetingRequest.self, from: data)
    }

    static func snapshot(in message: [String: Any]) -> MeetingSnapshot? {
        guard let data = message[snapshotKey] as? Data else { return nil }
        return try? JSONDecoder().decode(MeetingSnapshot.self, from: data)
    }
}
