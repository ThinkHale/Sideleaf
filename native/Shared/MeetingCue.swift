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

    init(
        id: UUID = UUID(),
        kind: Kind,
        prompt: String,
        quote: String = "",
        createdAt: Date = Date(),
        offset: TimeInterval = 0,
        dueDate: Date? = nil,
        state: State = .open,
        priority: Int = 50
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
    }

    var role: Role {
        switch kind {
        case .ask, .unanswered, .clarify, .figure, .term, .risk, .coverage: .ask
        case .commitment, .request, .deadline, .decision, .note: .remember
        }
    }

    var label: String {
        switch kind {
        case .ask: "Ask"
        case .unanswered: "Unanswered"
        case .clarify: "Pin down"
        case .commitment: "You said you would"
        case .request: "Asked of someone"
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
        switch kind {
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

    /// The web contract's annotation kind used when this cue is saved.
    var annotationKind: String {
        switch role {
        case .ask: "follow-up"
        case .remember: kind == .decision || kind == .note ? "important" : "action"
        }
    }

    var isOpen: Bool { state == .open }

    /// Cues the recap should keep unless the person dismissed them.
    var survivesRecap: Bool { state != .dismissed }
}

extension MeetingCue.State {
    var isResolved: Bool { self == .asked || self == .kept }
}
