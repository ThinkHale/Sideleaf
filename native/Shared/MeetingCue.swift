import Foundation

/// One thing Sideleaf noticed while listening: a question worth asking, a
/// commitment worth remembering, or a moment worth keeping.
///
/// Every cue is derived by explicit rules from the words that were actually
/// said, and every cue keeps the sentence it came from. Nothing here is a
/// model inference, and the person edits or dismisses anything before it is
/// saved.
struct MeetingCue: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        /// A question the transcript invites you to ask.
        case ask
        /// A question that was asked out loud and never clearly answered.
        case unanswered
        /// A vague phrase worth pinning down.
        case clarify
        /// Something you said you would do.
        case commitment
        /// Something someone was asked to do.
        case request
        /// A date or time that was named out loud.
        case deadline
        /// Something that was settled.
        case decision
        /// A figure worth reading back.
        case figure
        /// A term or acronym that was not explained.
        case term
        /// A blocker, risk or concern.
        case risk
        /// A point from your plan that has not come up yet.
        case coverage
        /// A moment the person kept themselves.
        case note
    }

    /// Where a cue belongs in the live view: something to say now, or
    /// something to keep.
    enum Role: String, Codable, Sendable { case ask, remember }


    enum State: String, Codable, Sendable {
        case open
        case asked
        case kept
        case dismissed
        /// The conversation itself answered this before anyone acted on it.
        case resolved
    }

    var id: UUID
    var kind: Kind
    /// The editable line shown to the person and saved with the page.
    var prompt: String
    /// The sentence this came from. Empty for cues derived from the plan.
    var quote: String
    var createdAt: Date
    /// Seconds from the start of the meeting, for the recap timeline.
    var offset: TimeInterval
    /// Set when a date was named out loud and could be resolved.
    var dueDate: Date?
    var state: State
    /// Higher wins when the live view can only show a few cues.
    var priority: Int
    /// What later speech did to this cue: the answer that closed it, the date
    /// that was finally named, the decision that replaced it. Always the words
    /// that caused the change, never a summary of them.
    var resolution: String?
    /// Who owes the action this cue describes. Optional because cues recorded
    /// before Sideleaf could attribute anything carry no answer.
    var owner: MeetingSpeaker?
    /// How `owner` was decided.
    var ownerSource: SpeakerSource?

    init(
        id: UUID = UUID(),
        kind: Kind,
        prompt: String,
        quote: String = "",
        createdAt: Date = Date(),
        offset: TimeInterval = 0,
        dueDate: Date? = nil,
        state: State = .open,
        priority: Int = 50,
        resolution: String? = nil,
        owner: MeetingSpeaker? = nil,
        ownerSource: SpeakerSource? = nil
    ) {
        self.id = id
        self.kind = kind
        self.prompt = prompt
        self.quote = quote
        self.createdAt = createdAt
        self.offset = offset
        self.dueDate = dueDate
        self.state = state
        self.priority = priority
        self.resolution = resolution
        self.owner = owner
        self.ownerSource = ownerSource
    }

    var role: Role { kind.role }

    /// Who owes this, with `unknown` standing for "nobody has said".
    var owedBy: MeetingSpeaker { owner ?? .unknown }

    var attributionSource: SpeakerSource { ownerSource ?? .assumed }

    /// True when the cue describes work someone has to do, so the question of
    /// whose work it is actually arises.
    var carriesWork: Bool { kind == .commitment || kind == .request }

    var label: String { kind.label(owedBy: owedBy) }
    var symbol: String { kind.symbol }
    /// The web contract's annotation kind used when this cue is saved.
    var annotationKind: String { kind.annotationKind }

    var isOpen: Bool { state == .open }

    /// Cues the recap should keep unless the person dismissed them.
    var survivesRecap: Bool { state != .dismissed }

    /// True once nobody needs to do anything about this any more.
    var isSettled: Bool { state != .open }

    /// The line a card shows under a cue the conversation caught up with.
    var resolutionNote: String? {
        guard state == .resolved, let resolution else { return nil }
        return resolution
    }
}

extension MeetingCue.Kind: Identifiable {
    var id: String { rawValue }

    var role: MeetingCue.Role {
        switch self {
        case .ask, .unanswered, .clarify, .figure, .term, .risk, .coverage: .ask
        case .commitment, .request, .deadline, .decision, .note: .remember
        }
    }

    var label: String { label(owedBy: .unknown) }

    /// The heading on a card. Work changes its name depending on who owes it,
    /// because "you said you would" and "they said they would" are different
    /// facts about the same sentence.
    func label(owedBy owner: MeetingSpeaker) -> String {
        switch self {
        case .ask: "Ask"
        case .unanswered: "Unanswered"
        case .clarify: "Pin down"
        case .commitment:
            switch owner {
            case .you, .unknown: "You said you would"
            case .other: "They said they would"
            }
        case .request:
            switch owner {
            case .you: "You were asked"
            case .other, .unknown: "You asked them"
            }
        case .deadline: "Date named"
        case .decision: "Decided"
        case .figure: "Check the figure"
        case .term: "Unexplained"
        case .risk: "Risk raised"
        case .coverage: "Not covered yet"
        case .note: "You kept this"
        }
    }

    var symbol: String {
        switch self {
        case .ask: "questionmark.bubble"
        case .unanswered: "questionmark.circle"
        case .clarify: "scope"
        case .commitment: "hand.raised"
        case .request: "arrow.turn.up.right"
        case .deadline: "calendar"
        case .decision: "checkmark.seal"
        case .figure: "number"
        case .term: "character.book.closed"
        case .risk: "exclamationmark.triangle"
        case .coverage: "list.bullet.rectangle"
        case .note: "star"
        }
    }

    /// The web contract's annotation kind used when a cue of this kind is saved.
    var annotationKind: String {
        switch role {
        case .ask: "follow-up"
        case .remember: self == .decision || self == .note ? "important" : "action"
        }
    }
}
