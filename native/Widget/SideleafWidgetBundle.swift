import SwiftUI
import WidgetKit

@main
struct SideleafWidgetBundle: WidgetBundle {
    var body: some Widget {
        MeetingWidget()
        MeetingControl()
    }
}
