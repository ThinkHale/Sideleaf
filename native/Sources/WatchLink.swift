import Foundation
import Observation
import WatchConnectivity

/// The iPhone half of the Apple Watch companion.
///
/// The phone holds the microphone and the cue engine, so the watch is a remote
/// control and a second screen: it sends start and stop, and it receives the
/// same small snapshot the Home Screen widget reads. No transcript is sent.
@MainActor
@Observable
final class WatchLink: NSObject {
    static let shared = WatchLink()

    private(set) var isSupported = WCSession.isSupported()
    private(set) var isPaired = false
    private(set) var isWatchAppInstalled = false
    private(set) var isReachable = false

    /// The last thing the wrist asked for. The root view observes this and
    /// acts on it while SwiftUI is updating, rather than from a stored closure
    /// that would capture a stale copy of the view.
    private(set) var pendingRequest: MeetingRequest?

    @ObservationIgnored private var lastSentSnapshot: MeetingSnapshot?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
        refreshState()
    }

    /// Sends the current picture of the meeting to the watch. The context is
    /// coalesced by the system, so this is safe to call on every change.
    func send(_ snapshot: MeetingSnapshot) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired,
              session.isWatchAppInstalled
        else { return }
        let bounded = snapshot.bounded()
        guard bounded != lastSentSnapshot else { return }
        lastSentSnapshot = bounded
        let payload = WatchMessage.payload(for: bounded)
        guard !payload.isEmpty else { return }
        try? session.updateApplicationContext(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in })
        }
    }

    func clearPendingRequest() {
        pendingRequest = nil
    }

    fileprivate func receive(_ request: MeetingRequest) {
        pendingRequest = request
    }

    fileprivate func refreshState() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
        isReachable = session.isReachable
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.refreshState()
            if let snapshot = self.lastSentSnapshot { self.send(snapshot) }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshState() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        // Decoded here so only Sendable values cross to the main actor.
        guard let request = WatchMessage.request(in: message) else { return }
        Task { @MainActor in self.receive(request) }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        replyHandler([WatchMessage.acknowledgementKey: true])
        guard let request = WatchMessage.request(in: message) else { return }
        Task { @MainActor in self.receive(request) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let request = WatchMessage.request(in: userInfo) else { return }
        Task { @MainActor in self.receive(request) }
    }
}
