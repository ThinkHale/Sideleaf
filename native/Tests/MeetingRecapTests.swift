import Foundation
import XCTest
@testable import Sideleaf

final class MeetingRecapTests: XCTestCase {
    private let startedAt = Date(timeIntervalSince1970: 1_790_071_200)

    private func draft(_ cues: [MeetingCue], plan: MeetingPlan? = nil) -> MeetingRecapDraft {
        MeetingRecapBuilder.build(
            plan: plan ?? MeetingPlan(kind: .meeting, title: "Pilot review", goal: "Agree a date"),
            cues: cues,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_500)
        )
    }

    func testEveryMarkAnchorsToTheExactWordsThatWereSaid() {
        let cues = [
            MeetingCue(kind: .unanswered, prompt: "Who owns the migration?", quote: "Who owns the migration?", offset: 30),
            MeetingCue(kind: .commitment, prompt: "Send the proposal", quote: "I'll send the proposal.", offset: 60),
            MeetingCue(kind: .decision, prompt: "Run the pilot in Leeds", quote: "We decided to run the pilot in Leeds.", offset: 90),
            MeetingCue(kind: .note, prompt: "Budget question", quote: "…about the budget.", offset: 120),
            MeetingCue(kind: .coverage, prompt: "Not covered: Pricing. Send it as a follow-up?", offset: 1_400),
        ]
        let result = draft(cues)
        let text = result.text as NSString
        XCTAssertEqual(result.annotations.count, cues.count)
        for annotation in result.annotations {
            XCTAssertEqual(
                text.substring(with: annotation.range),
                annotation.quote,
                "\(annotation.annotationKind) anchor drifted"
            )
        }
    }

    func testMarksUseTheSharedContractKinds() {
        let cues = [
            MeetingCue(kind: .ask, prompt: "When is that due?", quote: "We will do it soon.", offset: 10),
            MeetingCue(kind: .request, prompt: "Share the numbers", quote: "Can you share the numbers?", offset: 20),
            MeetingCue(kind: .decision, prompt: "Ship on Tuesday", quote: "We agreed to ship on Tuesday.", offset: 30),
        ]
        let kinds = draft(cues).annotations.map(\.annotationKind)
        XCTAssertEqual(kinds, ["follow-up", "action", "important"])
    }

    func testDismissedCuesAreLeftOut() {
        var dismissed = MeetingCue(kind: .ask, prompt: "Drop this", quote: "Noise.", offset: 10)
        dismissed.state = .dismissed
        let kept = MeetingCue(kind: .ask, prompt: "Keep this", quote: "Signal.", offset: 20)
        let result = draft([dismissed, kept])
        XCTAssertEqual(result.annotations.count, 1)
        XCTAssertFalse(result.text.contains("Drop this"))
        XCTAssertTrue(result.text.contains("Keep this"))
    }

    func testAskedQuestionsAreRecordedAsAddressed() {
        var asked = MeetingCue(kind: .unanswered, prompt: "Who owns it?", quote: "Who owns it?", offset: 10)
        asked.state = .asked
        XCTAssertEqual(draft([asked]).annotations.first?.state, "addressed")
    }

    func testHeadingsAppearOnlyForSectionsWithContent() {
        let cues = [MeetingCue(kind: .commitment, prompt: "Send the deck", quote: "I'll send the deck.", offset: 10)]
        let text = draft(cues).text
        XCTAssertTrue(text.contains(MeetingRecapBuilder.nextStepsHeading))
        XCTAssertFalse(text.contains(MeetingRecapBuilder.questionsHeading))
        XCTAssertFalse(text.contains(MeetingRecapBuilder.decidedHeading))
    }

    func testDueDatesAreWrittenIntoTheFollowUpText() {
        let due = startedAt.addingTimeInterval(86_400)
        let cue = MeetingCue(
            kind: .commitment,
            prompt: "Send the proposal",
            quote: "I'll send the proposal tomorrow.",
            offset: 10,
            dueDate: due
        )
        let annotation = draft([cue]).annotations.first
        XCTAssertTrue(annotation?.question.hasPrefix("Send the proposal — due ") == true)
    }

    func testAnEmptyMeetingStillSaysSo() {
        let result = draft([])
        XCTAssertTrue(result.text.contains("Nothing was kept from this meeting."))
        XCTAssertTrue(result.annotations.isEmpty)
    }

    func testHeaderCarriesTheTitleGoalAndLength() {
        let result = draft([])
        XCTAssertTrue(result.text.contains("Pilot review"))
        XCTAssertTrue(result.text.contains("25 min"))
        XCTAssertTrue(result.text.contains("Goal: Agree a date"))
        XCTAssertEqual(result.suggestedTitle, "Pilot review")
    }

    func testDurationReadsTheWayAPersonWouldSayIt() {
        XCTAssertEqual(MeetingRecapBuilder.durationText(20), "under a minute")
        XCTAssertEqual(MeetingRecapBuilder.durationText(600), "10 min")
        XCTAssertEqual(MeetingRecapBuilder.durationText(3_600), "1 hr")
        XCTAssertEqual(MeetingRecapBuilder.durationText(5_400), "1 hr 30 min")
    }

    func testUntitledMeetingsAreNamedForTheirKindAndTime() {
        let plan = MeetingPlan(kind: .interview, title: "   ")
        let suggested = MeetingRecapBuilder.suggestedTitle(plan: plan, startedAt: startedAt)
        XCTAssertTrue(suggested.hasPrefix("Interview · "))
    }
}
