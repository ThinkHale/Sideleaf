import Foundation
import XCTest
@testable import Sideleaf

final class MeetingIntelligenceTests: XCTestCase {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func engine(points: [String] = []) -> MeetingCueEngine {
        MeetingCueEngine(
            plan: MeetingPlan(kind: .meeting, title: "Test", points: points),
            calendar: calendar()
        )
    }

    // MARK: - Scanner

    func testScannerReturnsOnlyCompleteSentences() {
        let result = TranscriptScanner.scan("We start now. Then we pause", from: 0)
        XCTAssertEqual(result.sentences.map(\.text), ["We start now."])
        XCTAssertEqual(result.consumed, 13)
    }

    func testScannerResumesWhereItStopped() {
        let first = TranscriptScanner.scan("One thing. ", from: 0)
        let second = TranscriptScanner.scan("One thing. Another thing.", from: first.consumed)
        XCTAssertEqual(second.sentences.map(\.text), ["Another thing."])
    }

    func testScannerFlushesTheTailWhenAsked() {
        let result = TranscriptScanner.scan("No punctuation here", from: 0, flushTail: true)
        XCTAssertEqual(result.sentences.map(\.text), ["No punctuation here"])
        XCTAssertEqual(result.consumed, 19)
    }

    func testSentenceRangeMatchesTheQuotedWords() {
        let transcript = "  Ship it on Friday. "
        let sentence = TranscriptScanner.scan(transcript, from: 0).sentences[0]
        let quoted = (transcript as NSString).substring(with: sentence.range)
        XCTAssertEqual(quoted, sentence.text)
    }

    // MARK: - Detectors

    func testCommitmentBecomesAnActionWithItsDate() {
        var engine = engine()
        let now = Date(timeIntervalSince1970: 1_758_000_000)
        let cues = engine.ingest(
            transcript: "I'll send the revised proposal tomorrow.",
            elapsed: 30,
            now: now
        )
        let commitment = cues.first { $0.kind == .commitment }
        XCTAssertEqual(commitment?.prompt, "Send the revised proposal tomorrow")
        XCTAssertEqual(commitment?.annotationKind, "action")
        XCTAssertNotNil(commitment?.dueDate)
        XCTAssertEqual(commitment?.quote, "I'll send the revised proposal tomorrow.")
    }

    func testConditionalIsNotTreatedAsACommitment() {
        var engine = engine()
        let cues = engine.ingest(
            transcript: "If I will be free later we can look at it.",
            elapsed: 10,
            now: Date()
        )
        XCTAssertFalse(cues.contains { $0.kind == .commitment })
    }

    func testDecisionIsKeptAsAMark() {
        var engine = engine()
        let cues = engine.ingest(
            transcript: "So we decided to run the pilot in the Leeds office.",
            elapsed: 60,
            now: Date()
        )
        let decision = cues.first { $0.kind == .decision }
        XCTAssertEqual(decision?.prompt, "Run the pilot in the Leeds office")
        XCTAssertEqual(decision?.annotationKind, "important")
    }

    func testRequestBecomesANextStep() {
        var engine = engine()
        let cues = engine.ingest(
            transcript: "Can you share the current numbers with the team?",
            elapsed: 20,
            now: Date()
        )
        XCTAssertEqual(
            cues.first { $0.kind == .request }?.prompt,
            "Share the current numbers with the team"
        )
    }

    func testVagueTimingAsksForADate() {
        var engine = engine()
        let cues = engine.ingest(
            transcript: "We will get to the migration at some point.",
            elapsed: 15,
            now: Date()
        )
        let clarify = cues.first { $0.kind == .clarify }
        XCTAssertEqual(clarify?.prompt, "Can we put a date on \"at some point\"?")
        XCTAssertEqual(clarify?.annotationKind, "follow-up")
    }

    func testBlockerAsksWhatWouldUnblockIt() {
        var engine = engine()
        let cues = engine.ingest(
            transcript: "The rollout is blocked on the security review.",
            elapsed: 40,
            now: Date()
        )
        XCTAssertEqual(
            cues.first { $0.kind == .risk }?.prompt,
            "What would it take to unblock that?"
        )
    }

    func testUnexplainedAcronymIsAskedAboutOnce() {
        var engine = engine()
        let first = engine.ingest(
            transcript: "The SDR numbers look fine to me.",
            elapsed: 10,
            now: Date()
        )
        XCTAssertEqual(
            first.first { $0.kind == .term }?.prompt,
            "What does SDR stand for here?"
        )
        let second = engine.ingest(
            transcript: "The SDR numbers look fine to me. The SDR numbers are still fine.",
            elapsed: 300,
            now: Date()
        )
        XCTAssertFalse(second.contains { $0.kind == .term })
    }

    func testKnownAcronymsAreLeftAlone() {
        var engine = engine()
        let cues = engine.ingest(transcript: "The CEO is fine with it.", elapsed: 10, now: Date())
        XCTAssertFalse(cues.contains { $0.kind == .term })
    }

    func testFigureIsOfferedForReadBack() {
        var engine = engine()
        let cues = engine.ingest(
            transcript: "Renewals are sitting at 62 percent right now.",
            elapsed: 10,
            now: Date()
        )
        XCTAssertEqual(
            cues.first { $0.kind == .figure }?.prompt,
            "Can I read that back: 62 percent?"
        )
    }

    // MARK: - Unanswered questions

    func testQuestionWithNoRealAnswerComesBack() {
        var engine = engine()
        _ = engine.ingest(transcript: "Who owns the migration work?", elapsed: 10, now: Date())
        let cues = engine.ingest(
            transcript: "Who owns the migration work? Hmm. Not sure.",
            elapsed: 25,
            now: Date()
        )
        let unanswered = cues.first { $0.kind == .unanswered }
        XCTAssertEqual(unanswered?.prompt, "Who owns the migration work?")
        XCTAssertEqual(unanswered?.annotationKind, "follow-up")
    }

    func testAnsweredQuestionIsNotRaisedAgain() {
        var engine = engine()
        _ = engine.ingest(transcript: "Who owns the migration work?", elapsed: 10, now: Date())
        let cues = engine.ingest(
            transcript: "Who owns the migration work? Priya owns it and she has already started on the first two services this week.",
            elapsed: 30,
            now: Date()
        )
        XCTAssertFalse(cues.contains { $0.kind == .unanswered })
    }

    // MARK: - Plan coverage

    func testUncoveredPlanPointsBecomeFollowUps() {
        var engine = engine(points: ["Pricing", "Support handover"])
        _ = engine.ingest(
            transcript: "Pricing is settled for now.",
            elapsed: 60,
            now: Date()
        )
        let closing = engine.finish(transcript: "", elapsed: 300, now: Date())
        let coverage = closing.filter { $0.kind == .coverage }
        XCTAssertEqual(coverage.count, 1)
        XCTAssertTrue(coverage[0].prompt.contains("Support handover"))
        XCTAssertEqual(engine.planPoints.first { $0.text == "Pricing" }?.covered, true)
    }

    // MARK: - Noise control

    func testTheSameSuggestionIsNotRepeated() {
        var engine = engine()
        let first = engine.ingest(
            transcript: "The launch is blocked on legal.",
            elapsed: 10,
            now: Date()
        )
        let second = engine.ingest(
            transcript: "The launch is blocked on legal. The launch is blocked on legal.",
            elapsed: 600,
            now: Date()
        )
        XCTAssertEqual(first.filter { $0.kind == .risk }.count, 1)
        XCTAssertTrue(second.isEmpty)
    }

    func testLowerValueCuesRespectACooldown() {
        var engine = engine()
        _ = engine.ingest(transcript: "It is roughly the same size.", elapsed: 10, now: Date())
        let soon = engine.ingest(
            transcript: "It is roughly the same size. There were a bunch of requests about it.",
            elapsed: 20,
            now: Date()
        )
        XCTAssertTrue(soon.filter { $0.kind == .clarify }.isEmpty)
    }

    func testEveryCueKeepsTheWordsItCameFrom() {
        var engine = engine()
        let cues = engine.ingest(
            transcript: "I'll write the summary. We agreed to ship on Tuesday. It is blocked on legal.",
            elapsed: 30,
            now: Date()
        )
        XCTAssertFalse(cues.isEmpty)
        for cue in cues where cue.kind != .coverage {
            XCTAssertFalse(cue.quote.isEmpty, "\(cue.kind) lost its source")
        }
    }
}
