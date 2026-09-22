import Foundation

/// One annotation the recap wants to create, positioned inside the recap text.
///
/// Ranges are UTF-16 offsets relative to the start of the recap block, which is
/// the convention the shared web contract anchors with.
struct RecapAnnotationDraft: Equatable, Sendable {
    var cueID: UUID
    /// "follow-up", "action" or "important" from the shared document contract.
    var annotationKind: String
    var question: String
    var quote: String
    var range: NSRange
    var state: String
}

/// The block of notes a finished meeting adds to a page, and the marks that
/// point into it.
struct MeetingRecapDraft: Equatable, Sendable {
    var text: String
    var annotations: [RecapAnnotationDraft]
    var suggestedTitle: String

    var isEmpty: Bool { text.isEmpty }
}

/// Writes the recap a person actually wants after a meeting: what to ask, what
/// they owe, what was settled, and what never came up.
///
/// The recap is plain text so it reads the same in the notebook, in an export
/// and on the web. Marks anchor to the exact words that were said, so the web
/// app links each follow-up back to its source.
enum MeetingRecapBuilder {
    static let questionsHeading = "Questions to ask or send"
    static let answeredHeading = "Answered in the meeting"
    static let nextStepsHeading = "Your next steps"
    static let decidedHeading = "Decided"
    static let reversedHeading = "Reversed later"
    static let markedHeading = "Moments you kept"
    static let notCoveredHeading = "Not covered"
    static let heardPrefix = "Heard: "

    static func build(
        plan: MeetingPlan,
        cues: [MeetingCue],
        startedAt: Date,
        endedAt: Date,
        calendar: Calendar = .current
    ) -> MeetingRecapDraft {
        var builder = Builder()
        let kept = cues.filter(\.survivesRecap)
        let duration = max(0, endedAt.timeIntervalSince(startedAt))

        builder.line(
            "\(plan.displayTitle) · \(plan.kind.title) · \(durationText(duration)) · "
                + startedAt.formatted(date: .abbreviated, time: .shortened)
        )
        let goal = plan.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        if !goal.isEmpty { builder.line("Goal: \(goal)") }

        // A question the room answered is no longer a question to send, and a
        // decision that was taken back is not a decision. Both stay in the
        // recap, under headings that say what actually happened.
        let asks = kept.filter { $0.role == .ask && $0.kind != .coverage }
        let questions = asks.filter { $0.state != .resolved }.sorted { $0.offset < $1.offset }
        let answered = asks.filter { $0.state == .resolved }.sorted { $0.offset < $1.offset }
        let steps = kept
            .filter { $0.kind == .commitment || $0.kind == .request || $0.kind == .deadline }
            .sorted { $0.offset < $1.offset }
        let settledDecisions = kept.filter { $0.kind == .decision }
        let decisions = settledDecisions
            .filter { $0.state != .resolved }
            .sorted { $0.offset < $1.offset }
        let reversed = settledDecisions
            .filter { $0.state == .resolved }
            .sorted { $0.offset < $1.offset }
        let marked = kept.filter { $0.kind == .note }.sorted { $0.offset < $1.offset }
        let uncovered = kept
            .filter { $0.kind == .coverage && $0.state != .resolved }
            .sorted { $0.offset < $1.offset }

        section(questionsHeading, questions, into: &builder)
        section(nextStepsHeading, steps, into: &builder)
        section(decidedHeading, decisions, into: &builder)
        section(markedHeading, marked, into: &builder)
        section(answeredHeading, answered, into: &builder)
        section(reversedHeading, reversed, into: &builder)
        section(notCoveredHeading, uncovered, into: &builder)

        let everything = [questions, steps, decisions, marked, answered, reversed, uncovered]
        if everything.allSatisfy(\.isEmpty) {
            builder.blank()
            builder.line("Nothing was kept from this meeting.")
        }

        return MeetingRecapDraft(
            text: builder.text,
            annotations: builder.annotations,
            suggestedTitle: suggestedTitle(plan: plan, startedAt: startedAt)
        )
    }

    static func suggestedTitle(plan: MeetingPlan, startedAt: Date) -> String {
        let title = plan.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return String(title.prefix(120)) }
        return "\(plan.kind.defaultTitle) · \(startedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        if minutes < 1 { return "under a minute" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) hr" : "\(hours) hr \(remainder) min"
    }

    /// The line a bullet shows, including a resolved due date when there is one.
    static func bulletText(for cue: MeetingCue) -> String {
        guard let due = cue.dueDate else { return cue.prompt }
        return "\(cue.prompt) (due \(due.formatted(date: .abbreviated, time: .shortened)))"
    }

    private static func section(
        _ heading: String,
        _ cues: [MeetingCue],
        into builder: inout Builder
    ) {
        guard !cues.isEmpty else { return }
        builder.blank()
        builder.line(heading)
        for cue in cues {
            let bullet = bulletText(for: cue)
            let bulletRange = builder.line("• \(bullet)", highlighting: bullet)
            var anchorRange = bulletRange
            var quote = bullet
            if !cue.quote.isEmpty {
                let heard = "\(heardPrefix)\u{201C}\(cue.quote)\u{201D}"
                anchorRange = builder.line("  \(heard)", highlighting: cue.quote)
                quote = cue.quote
            }
            // What later speech did to this, in the words that did it.
            if let resolution = cue.resolution, !resolution.isEmpty {
                builder.line("  \(resolution)")
            }
            let settled = cue.state == .asked || cue.state == .resolved
            builder.annotations.append(
                RecapAnnotationDraft(
                    cueID: cue.id,
                    annotationKind: cue.annotationKind,
                    question: cue.annotationKind == "important" ? "" : bullet,
                    quote: quote,
                    range: anchorRange,
                    state: settled ? "addressed" : "open"
                )
            )
        }
    }

    /// Accumulates the recap text while recording where each quote landed.
    private struct Builder {
        var text = ""
        var annotations: [RecapAnnotationDraft] = []

        /// Appends a line and returns the range of `highlight` inside it.
        @discardableResult
        mutating func line(_ value: String, highlighting highlight: String? = nil) -> NSRange {
            let start = (text as NSString).length
            text += value + "\n"
            guard let highlight, !highlight.isEmpty else {
                return NSRange(location: start, length: (value as NSString).length)
            }
            let found = (value as NSString).range(of: highlight)
            guard found.location != NSNotFound else {
                return NSRange(location: start, length: (value as NSString).length)
            }
            return NSRange(location: start + found.location, length: found.length)
        }

        mutating func blank() {
            text += "\n"
        }
    }
}
