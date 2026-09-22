import Foundation
import SwiftData

/// What actually reached the page when a meeting was saved.
struct MeetingSaveOutcome: Equatable, Sendable {
    var savedRecap: Bool
    var savedTranscript: Bool
    var message: String?

    var isComplete: Bool { savedRecap && message == nil }
}

extension NotebookSync {
    /// Creates the page a meeting will be written to, owned by the signed-in
    /// account when there is one.
    @discardableResult
    func newPage(titled title: String, context: ModelContext) -> LocalPage {
        let page = LocalPage(title: title)
        if let identity {
            page.ownerUserID = identity.id
            page.cloudBlockID = page.id
            page.pendingMutationID = UUID()
        }
        context.insert(page)
        return page
    }

    /// Writes a finished meeting into a page.
    ///
    /// The recap is appended to the typed notes as ordinary text, and each kept
    /// cue becomes a mark anchored to the exact words it came from. Those marks
    /// use the shared web contract's kinds, so a follow-up captured on iPhone
    /// appears in the browser margin with its source quote intact.
    func saveMeeting(
        draft: MeetingRecapDraft,
        transcript: String,
        plan: MeetingPlan,
        endedAt: Date,
        to page: LocalPage,
        context: ModelContext
    ) -> MeetingSaveOutcome {
        let existing = page.text
        let separator = existing.isEmpty ? "" : "\n\n"
        let prefixLength = ((existing + separator) as NSString).length
        let combined = existing + separator + draft.text
        guard combined.utf16.count <= NotebookSync.personalBlockTextLimit else {
            return MeetingSaveOutcome(
                savedRecap: false,
                savedTranscript: false,
                message: "This page is too full for another recap. Start the meeting on a new page; nothing was changed."
            )
        }

        let revision = page.textRevision + 1
        let previousText = page.text
        let previousRevision = page.textRevision
        let previousAnnotations = page.annotations
        let previousTitle = page.title

        page.text = combined
        page.textRevision = revision
        var annotations = page.annotations.map { existing -> NativeAnnotation in
            var updated = existing
            updated.anchor = existing.anchor.remapped(to: combined, revision: revision)
            return updated
        }
        let length = (combined as NSString).length
        for item in draft.annotations {
            let range = NSRange(
                location: item.range.location + prefixLength,
                length: item.range.length
            )
            guard range.location >= 0, range.length > 0, NSMaxRange(range) <= length else { continue }
            annotations.append(
                NativeAnnotation(
                    id: item.cueID,
                    kind: item.annotationKind,
                    anchor: .make(
                        blockId: page.id,
                        revision: revision,
                        text: combined,
                        range: range
                    ),
                    question: String(item.question.prefix(2_000)),
                    state: item.state,
                    createdAt: endedAt
                )
            )
        }
        page.annotations = annotations
        page.meetingKind = plan.kind.rawValue
        page.meetingEndedAt = endedAt
        if isPlaceholderTitle(page.title) {
            page.title = draft.suggestedTitle
        }

        guard pageDidChange(page, context: context) else {
            page.text = previousText
            page.textRevision = previousRevision
            page.annotations = previousAnnotations
            page.title = previousTitle
            return MeetingSaveOutcome(
                savedRecap: false,
                savedTranscript: false,
                message: "Sideleaf could not save this recap on the device. Keep Sideleaf open and try again."
            )
        }

        let spoken = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else {
            return MeetingSaveOutcome(savedRecap: true, savedTranscript: false, message: nil)
        }
        let transcriptMessage = appendTranscript(spoken, to: page, context: context)
        return MeetingSaveOutcome(
            savedRecap: true,
            savedTranscript: transcriptMessage == nil,
            message: transcriptMessage
        )
    }

    /// Pages that hold a saved meeting, newest first.
    func meetingPages(from pages: [LocalPage], limit: Int = 5) -> [LocalPage] {
        visiblePages(from: pages)
            .filter { $0.meetingEndedAt != nil }
            .sorted { ($0.meetingEndedAt ?? .distantPast) > ($1.meetingEndedAt ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }

    private func isPlaceholderTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "Untitled page"
    }
}
