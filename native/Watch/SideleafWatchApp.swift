import SwiftUI

@main
struct SideleafWatchApp: App {
    @State private var connection = WatchConnection.shared

    var body: some Scene {
        WindowGroup {
            WatchMeetingView()
                .environment(connection)
                .task { connection.activate() }
        }
    }
}
