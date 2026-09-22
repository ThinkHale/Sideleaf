import Foundation
import Observation
import WatchConnectivity
import WatchKit

/// The watch half of the companion.
///
/// The iPhone does the listening. This holds the latest snapshot it sent, taps
/// the wrist when a new question arrives, and forwards start, stop and mark
/// requests back to the phone.
@MainActor
@Observable
final class WatchConnection: NSObject {
    static let shared = WatchConnection()

    private(set) var snapshot = MeetingSnapshot.idle
    private(set) var isReachable = false
    private(set) var notice: String?
    /// Set while a request is on its way, so a button can show it was heard.
    private(set) var pendingAction: MeetingRequest.Action?

    @ObservationIgnored private var announcedCueID: UUID?
    @ObservationIgnored private var pendingSince: Date?

    /// A request is only shown as pending for this long before the button
    /// becomes usable again.
    static let pendingWindow: TimeInterval = 6

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated { session.activate() }
        isReachable = session.isReachable
        if let context = WatchMessage.snapshot(in: session.receivedApplicationContext) {
            apply(context)
        }
    }

    func send(_ request: MeetingRequest) {
        guard WCSession.isSupported() else {
            notice = "This watch cannot reach your iPhone."
            return
        }
        pendingAction = request.action
        pendingSince = Date()
        notice = nil
        let session = WCSession.default
        let payload = WatchMessage.payload(for: request)
        guard !payload.isEmpty else { return }
        if session.isReachable {
            session.sendMessage(
                payload,
                replyHandler: { _ in },
                errorHandler: { [weak self] _ in
                    Task { @MainActor in self?.fallback(payload) }
                }
            )
        } else {
            fallback(payload)
        }
    }

    /// True once a request has been waiting long enough that the phone is
    /// probably not listening.
    func isPending(_ action: MeetingRequest.Action, now: Date = Date()) -> Bool {
        guard pendingAction == action, let pendingSince else { return false }
        return now.timeIntervalSince(pendingSince) < Self.pendingWindow
    }

    private func fallback(_ payload: [String: Any]) {
        WCSession.default.transferUserInfo(payload)
        notice = "Sent to your iPhone. Open Sideleaf there if it does not start."
    }

    fileprivate func apply(_ snapshot: MeetingSnapshot) {
        let previous = self.snapshot
        self.snapshot = snapshot
        if previous.phase != snapshot.phase { pendingAction = nil }
        guard let newest = snapshot.topCues.first else { return }
        guard newest.id != announcedCueID else { return }
        announcedCueID = newest.id
        guard previous.isLive, snapshot.isLive else { return }
        WKInterfaceDevice.current().play(.notification)
    }

    fileprivate func updateReachability(_ reachable: Bool) {
        isReachable = reachable
    }
}

extension WatchConnection: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let reachable = activationState == .activated
        Task { @MainActor in self.updateReachability(reachable && WCSession.default.isReachable) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.updateReachability(reachable) }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let snapshot = WatchMessage.snapshot(in: applicationContext) else { return }
        Task { @MainActor in self.apply(snapshot) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let snapshot = WatchMessage.snapshot(in: message) else { return }
        Task { @MainActor in self.apply(snapshot) }
    }
}
