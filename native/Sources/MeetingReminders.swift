import Foundation
import Observation
import UserNotifications

/// Local reminders for the things a meeting left you holding.
///
/// Reminders are scheduled on this device by Apple's notification service. No
/// reminder text leaves the device, and nothing is scheduled without an
/// explicit tap.
@MainActor
@Observable
final class MeetingReminders {
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var scheduled: Set<UUID> = []
    private(set) var errorMessage: String?

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    /// The soonest a reminder is allowed to fire, so a date that has already
    /// passed still produces something useful.
    static let minimumLeadTime: TimeInterval = 60

    var canSchedule: Bool {
        authorization != .denied
    }

    func refresh() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    /// Returns the date a reminder would use if the person accepts it.
    static func suggestedDate(
        for cue: MeetingCue,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        if let due = cue.dueDate, due > now.addingTimeInterval(minimumLeadTime) { return due }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        var components = calendar.dateComponents(
            [.year, .month, .day],
            from: tomorrow ?? now.addingTimeInterval(86_400)
        )
        components.hour = MeetingDates.defaultHour
        components.minute = 0
        return calendar.date(from: components) ?? now.addingTimeInterval(3_600)
    }

    @discardableResult
    func schedule(
        _ cue: MeetingCue,
        at date: Date,
        meetingTitle: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async -> Bool {
        guard await ensureAuthorization() else { return false }
        let fireDate = max(date, now.addingTimeInterval(Self.minimumLeadTime))
        let content = UNMutableNotificationContent()
        content.title = meetingTitle.isEmpty ? "Sideleaf" : meetingTitle
        content.body = cue.prompt
        content.sound = .default
        content.interruptionLevel = .active
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let request = UNNotificationRequest(
            identifier: cue.id.uuidString,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        do {
            try await center.add(request)
            scheduled.insert(cue.id)
            errorMessage = nil
            return true
        } catch {
            errorMessage = "That reminder could not be scheduled on this device."
            return false
        }
    }

    func cancel(_ cue: MeetingCue) {
        center.removePendingNotificationRequests(withIdentifiers: [cue.id.uuidString])
        scheduled.remove(cue.id)
    }

    func cancelAll(_ cues: [MeetingCue]) {
        let identifiers = cues.map(\.id.uuidString)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        for cue in cues { scheduled.remove(cue.id) }
    }

    /// Asks once, then remembers the answer the system gave.
    private func ensureAuthorization() async -> Bool {
        await refresh()
        switch authorization {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            errorMessage = "Notifications are off for Sideleaf. Turn them on in Settings to use reminders."
            return false
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                await refresh()
                if !granted {
                    errorMessage = "Reminders need notification permission."
                }
                return granted
            } catch {
                errorMessage = "Notification permission could not be requested."
                return false
            }
        @unknown default:
            return false
        }
    }
}
