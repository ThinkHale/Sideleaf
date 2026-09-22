import AppIntents

/// Siri and the Shortcuts app reach the same two actions the widget offers.
struct SideleafShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartMeetingIntent(),
            phrases: [
                "Start a \(.applicationName) meeting",
                "Start listening with \(.applicationName)",
                "Take notes with \(.applicationName)",
            ],
            shortTitle: "Start a meeting",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: StopMeetingIntent(),
            phrases: [
                "End my \(.applicationName) meeting",
                "Stop \(.applicationName)",
            ],
            shortTitle: "End the meeting",
            systemImageName: "stop.fill"
        )
    }
}
