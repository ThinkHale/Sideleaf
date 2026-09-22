import Foundation

/// What the person is sitting in. The kind changes the starter plan and the
/// wording Sideleaf uses, not which detectors run.
enum MeetingKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case meeting
    case interview
    case lecture
    case oneToOne
    case call

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meeting: "Meeting"
        case .interview: "Interview"
        case .lecture: "Class or talk"
        case .oneToOne: "One to one"
        case .call: "Call"
        }
    }

    var symbol: String {
        switch self {
        case .meeting: "person.3"
        case .interview: "person.crop.rectangle"
        case .lecture: "graduationcap"
        case .oneToOne: "person.2"
        case .call: "phone"
        }
    }

    /// A short line describing what Sideleaf will listen for.
    var focus: String {
        switch self {
        case .meeting: "Decisions, owners and dates"
        case .interview: "Claims to probe and answers left hanging"
        case .lecture: "Terms, definitions and what to review"
        case .oneToOne: "Commitments on both sides"
        case .call: "What you agreed to do next"
        }
    }

    /// Starter points to cover. The person edits these before starting.
    var suggestedPlan: [String] {
        switch self {
        case .meeting: ["Where things stand", "Decisions needed", "Next steps and owners"]
        case .interview: ["Background", "A worked example", "Questions for them"]
        case .lecture: ["Main argument", "Terms to define", "What is assessed"]
        case .oneToOne: ["Since last time", "Blockers", "What I need from you"]
        case .call: ["Purpose of the call", "Open questions", "Next step"]
        }
    }

    var defaultTitle: String {
        switch self {
        case .meeting: "Meeting"
        case .interview: "Interview"
        case .lecture: "Class"
        case .oneToOne: "One to one"
        case .call: "Call"
        }
    }
}
