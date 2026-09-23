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
        XCTAssertTrue(annotation?.question.hasPrefix("Send the proposal (due ") == true)
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

    // MARK: - What the conversation settled

    func testAnsweredQuestionsLeaveTheSendList() {
        var answered = MeetingCue(
            kind: .unanswered,
            prompt: "Who owns the migration?",
            quote: "Who owns the migration?",
            offset: 10
        )
        answered.state = .resolved
        answered.resolution = "Answered: Priya owns it."
        let open = MeetingCue(kind: .ask, prompt: "When is that due?", quote: "Soon.", offset: 20)
        let result = draft([answered, open])
        let text = result.text
        XCTAssertTrue(text.contains(MeetingRecapBuilder.answeredHeading))
        XCTAssertTrue(text.contains("Answered: Priya owns it."))
        let sendList = text.components(separatedBy: MeetingRecapBuilder.answeredHeading)[0]
        XCTAssertTrue(sendList.contains("When is that due?"))
        XCTAssertFalse(sendList.contains("Who owns the migration?"))
    }

    func testReversedDecisionsAreNotListedAsDecisions() {
        var reversed = MeetingCue(
            kind: .decision,
            prompt: "Run the pilot in Leeds",
            quote: "We decided to run the pilot in Leeds.",
            offset: 10
        )
        reversed.state = .resolved
        reversed.resolution = "Changed later: Actually let us run it in Manchester."
        let result = draft([reversed])
        XCTAssertTrue(result.text.contains(MeetingRecapBuilder.reversedHeading))
        XCTAssertFalse(result.text.contains(MeetingRecapBuilder.decidedHeading))
        XCTAssertEqual(result.annotations.first?.state, "addressed")
    }

    func testPointsCoveredLaterAreNotListedAsGaps() {
        var covered = MeetingCue(kind: .coverage, prompt: "Not covered: Pricing.", offset: 30)
        covered.state = .resolved
        covered.resolution = "Covered: Pricing is agreed."
        let result = draft([covered])
        XCTAssertFalse(result.text.contains(MeetingRecapBuilder.notCoveredHeading))
        XCTAssertTrue(result.annotations.isEmpty)
    }

    func testAResolvedItemStillAnchorsToTheWordsThatWereSaid() {
        var answered = MeetingCue(
            kind: .clarify,
            prompt: "Can we put a date on \"soon\"?",
            quote: "We will get to it soon.",
            offset: 10
        )
        answered.state = .resolved
        answered.resolution = "Answered: Friday"
        let result = draft([answered])
        let text = result.text as NSString
        guard let annotation = result.annotations.first else {
            return XCTFail("expected one mark")
        }
        XCTAssertEqual(text.substring(with: annotation.range), annotation.quote)
        XCTAssertTrue(result.text.contains("Answered: Friday"))
    }

    func testWorkTheySignedUpForGetsItsOwnHeading() {
        let yours = MeetingCue(
            kind: .commitment,
            prompt: "Send the deck",
            quote: "I'll send the deck.",
            offset: 10,
            owner: .you,
            ownerSource: .voice
        )
        let theirs = MeetingCue(
            kind: .commitment,
            prompt: "Send the signed contract",
            quote: "I'll send the signed contract.",
            offset: 20,
            owner: .other,
            ownerSource: .voice
        )
        let text = draft([yours, theirs]).text
        XCTAssertTrue(text.contains(MeetingRecapBuilder.nextStepsHeading))
        XCTAssertTrue(text.contains(MeetingRecapBuilder.theirStepsHeading))
        let mine = text.components(separatedBy: MeetingRecapBuilder.theirStepsHeading)[0]
        XCTAssertTrue(mine.contains("Send the deck"))
        XCTAssertFalse(mine.contains("Send the signed contract"))
    }

    func testUnattributedWorkStaysOnYourList() {
        let cue = MeetingCue(
            kind: .commitment,
            prompt: "Send the deck",
            quote: "I'll send the deck.",
            offset: 10
        )
        let text = draft([cue]).text
        XCTAssertTrue(text.contains(MeetingRecapBuilder.nextStepsHeading))
        XCTAssertFalse(text.contains(MeetingRecapBuilder.theirStepsHeading))
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
