#if os(iOS)
import AppIntents
import Foundation

extension MeetingKind: AppEnum {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Meeting kind")

    static var caseDisplayRepresentations: [MeetingKind: DisplayRepresentation] {
        [
            .meeting: DisplayRepresentation(title: "Meeting", image: DisplayRepresentation.Image(systemName: "person.3")),
            .interview: DisplayRepresentation(title: "Interview", image: DisplayRepresentation.Image(systemName: "person.crop.rectangle")),
            .lecture: DisplayRepresentation(title: "Class or talk", image: DisplayRepresentation.Image(systemName: "graduationcap")),
            .oneToOne: DisplayRepresentation(title: "One to one", image: DisplayRepresentation.Image(systemName: "person.2")),
            .call: DisplayRepresentation(title: "Call", image: DisplayRepresentation.Image(systemName: "phone")),
        ]
    }
}

/// Chooses what a Home Screen widget starts.
struct MeetingWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Sideleaf meeting"
    static let description = IntentDescription("Choose what this widget starts listening for.")

    @Parameter(title: "Kind", default: .meeting)
    var kind: MeetingKind

    init() {}

    init(kind: MeetingKind) {
        self.kind = kind
    }
}

/// Starts listening. The microphone belongs to the app, so this always brings
/// Sideleaf forward rather than opening a microphone from a widget process.
struct StartMeetingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a meeting"
    static let description = IntentDescription(
        "Opens Sideleaf and starts listening on this device for questions to ask and things to remember."
    )
    static let openAppWhenRun = true

    @Parameter(title: "Kind", default: .meeting)
    var kind: MeetingKind

    init() {}

    init(kind: MeetingKind) {
        self.kind = kind
    }

    func perform() async throws -> some IntentResult {
        MeetingSharedStore.submit(MeetingRequest(action: .start, kind: kind))
        return .result()
    }
}

/// Ends the meeting and brings the recap forward, where the person decides
/// what is saved.
struct StopMeetingIntent: AppIntent {
    static let title: LocalizedStringResource = "End the meeting"
    static let description = IntentDescription("Stops listening and opens the Sideleaf recap.")
    static let openAppWhenRun = true

    init() {}

    func perform() async throws -> some IntentResult {
        MeetingSharedStore.submit(MeetingRequest(action: .stop))
        return .result()
    }
}

/// Opens the live meeting without changing it.
struct OpenMeetingIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Sideleaf"
    static let description = IntentDescription("Opens the current Sideleaf meeting.")
    static let openAppWhenRun = true

    init() {}

    func perform() async throws -> some IntentResult {
        MeetingSharedStore.submit(MeetingRequest(action: .open))
        return .result()
    }
}
#endif
