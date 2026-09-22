import AppIntents
import SwiftUI
import WidgetKit

/// A Control Center, Lock Screen and Action button control that starts
/// listening in one press.
struct MeetingControl: ControlWidget {
    static let kind = "SideleafMeetingControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartMeetingIntent()) {
                Label("Start meeting", systemImage: "waveform")
            }
        }
        .displayName("Start a Sideleaf meeting")
        .description("Opens Sideleaf and starts listening on this device.")
    }
}
