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
        ).created
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
        ).created
        XCTAssertFalse(cues.contains { $0.kind == .commitment })
    }

    func testDecisionIsKeptAsAMark() {
        var engine = engine()
        let cues = engine.ingest(
            transcript: "So we decided to run the pilot in the Leeds office.",
            elapsed: 60,
            now: Date()
        ).created
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
        ).created
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
        ).created
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
        ).created
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
        ).created
        XCTAssertEqual(
            first.first { $0.kind == .term }?.prompt,
            "What does SDR stand for here?"
        )
        let second = engine.ingest(
            transcript: "The SDR numbers look fine to me. The SDR numbers are still fine.",
            elapsed: 300,
            now: Date()
        ).created
        XCTAssertFalse(second.contains { $0.kind == .term })
    }

    func testKnownAcronymsAreLeftAlone() {
        var engine = engine()
        let cues = engine.ingest(transcript: "The CEO is fine with it.", elapsed: 10, now: Date()).created
        XCTAssertFalse(cues.contains { $0.kind == .term })
    }

    func testFigureIsOfferedForReadBack() {
        var engine = engine()
        let cues = engine.ingest(
            transcript: "Renewals are sitting at 62 percent right now.",
            elapsed: 10,
            now: Date()
        ).created
        XCTAssertEqual(
            cues.first { $0.kind == .figure }?.prompt,
            "Can I read that back: 62 percent?"
        )
    }

    // MARK: - Unanswered questions

    func testQuestionWithNoRealAnswerComesBack() {
        var engine = engine()
        _ = engine.ingest(transcript: "Who owns the migration work?", elapsed: 10, now: Date()).created
        let cues = engine.ingest(
            transcript: "Who owns the migration work? Hmm. Not sure.",
            elapsed: 25,
            now: Date()
        ).created
        let unanswered = cues.first { $0.kind == .unanswered }
        XCTAssertEqual(unanswered?.prompt, "Who owns the migration work?")
        XCTAssertEqual(unanswered?.annotationKind, "follow-up")
    }

    func testAnsweredQuestionIsNotRaisedAgain() {
        var engine = engine()
        _ = engine.ingest(transcript: "Who owns the migration work?", elapsed: 10, now: Date()).created
        let cues = engine.ingest(
            transcript: "Who owns the migration work? Priya owns it and she has already started on the first two services this week.",
            elapsed: 30,
            now: Date()
        ).created
        XCTAssertFalse(cues.contains { $0.kind == .unanswered })
    }

    // MARK: - Plan coverage

    func testUncoveredPlanPointsBecomeFollowUps() {
        var engine = engine(points: ["Pricing", "Support handover"])
        _ = engine.ingest(
            transcript: "Pricing is settled for now.",
            elapsed: 60,
            now: Date()
        ).created
        let closing = engine.finish(transcript: "", elapsed: 300, now: Date()).created
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
        ).created
        let second = engine.ingest(
            transcript: "The launch is blocked on legal. The launch is blocked on legal.",
            elapsed: 600,
            now: Date()
        ).created
        XCTAssertEqual(first.filter { $0.kind == .risk }.count, 1)
        XCTAssertTrue(second.isEmpty)
    }

    func testLowerValueCuesRespectACooldown() {
        var engine = engine()
        _ = engine.ingest(transcript: "It is roughly the same size.", elapsed: 10, now: Date()).created
        let soon = engine.ingest(
            transcript: "It is roughly the same size. There were a bunch of requests about it.",
            elapsed: 20,
            now: Date()
        ).created
        XCTAssertTrue(soon.filter { $0.kind == .clarify }.isEmpty)
    }

    func testEveryCueKeepsTheWordsItCameFrom() {
        var engine = engine()
        let cues = engine.ingest(
            transcript: "I'll write the summary. We agreed to ship on Tuesday. It is blocked on legal.",
            elapsed: 30,
            now: Date()
        ).created
        XCTAssertFalse(cues.isEmpty)
        for cue in cues where cue.kind != .coverage {
            XCTAssertFalse(cue.quote.isEmpty, "\(cue.kind) lost its source")
        }
    }
}

/// Sideleaf keeps listening after it has spoken: a suggestion stands only until
/// the conversation answers it.
final class MeetingCueReconciliationTests: XCTestCase {
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

    func testVagueTimingClosesWhenADateIsNamed() {
        var engine = engine()
        let opening = "We will get to the migration at some point."
        _ = engine.ingest(transcript: opening, elapsed: 10, now: Date())
        let changes = engine.ingest(
            transcript: opening + " Let us do the migration on Friday.",
            elapsed: 40,
            now: Date()
        )
        let clarify = changes.revised.first { $0.kind == .clarify }
        XCTAssertEqual(clarify?.state, .resolved)
        XCTAssertEqual(clarify?.resolution, "Answered: Friday")
        XCTAssertNotNil(clarify?.dueDate)
    }

    func testUnansweredQuestionClosesWhenItIsAnsweredLater() {
        var engine = engine()
        let asked = "Who owns the migration work?"
        _ = engine.ingest(transcript: asked, elapsed: 10, now: Date())
        let raised = engine.ingest(
            transcript: asked + " Hmm. Not sure.",
            elapsed: 30,
            now: Date()
        )
        XCTAssertTrue(raised.created.contains { $0.kind == .unanswered })
        let changes = engine.ingest(
            transcript: asked + " Hmm. Not sure. Priya owns the migration work and has started on it.",
            elapsed: 90,
            now: Date()
        )
        let unanswered = changes.revised.first { $0.kind == .unanswered }
        XCTAssertEqual(unanswered?.state, .resolved)
        XCTAssertEqual(unanswered?.resolution?.hasPrefix("Answered: Priya owns"), true)
    }

    func testAcronymClosesWhenItIsExplained() {
        var engine = engine()
        let opening = "The SDR numbers look fine to me."
        _ = engine.ingest(transcript: opening, elapsed: 10, now: Date())
        let changes = engine.ingest(
            transcript: opening + " SDR stands for sales development representative.",
            elapsed: 40,
            now: Date()
        )
        XCTAssertEqual(changes.revised.first { $0.kind == .term }?.state, .resolved)
    }

    func testBlockerClosesWhenItIsCleared() {
        var engine = engine()
        let opening = "The rollout is blocked on the security review."
        _ = engine.ingest(transcript: opening, elapsed: 10, now: Date())
        let changes = engine.ingest(
            transcript: opening + " The security review is cleared now.",
            elapsed: 120,
            now: Date()
        )
        let risk = changes.revised.first { $0.kind == .risk }
        XCTAssertEqual(risk?.state, .resolved)
        XCTAssertEqual(risk?.resolution?.hasPrefix("Cleared:"), true)
    }

    func testDecisionIsMarkedWhenItIsTakenBack() {
        var engine = engine()
        let opening = "We decided to run the pilot in Leeds."
        _ = engine.ingest(transcript: opening, elapsed: 10, now: Date())
        let changes = engine.ingest(
            transcript: opening + " Actually let us run the pilot in Manchester.",
            elapsed: 200,
            now: Date()
        )
        let decision = changes.revised.first { $0.kind == .decision }
        XCTAssertEqual(decision?.state, .resolved)
        XCTAssertEqual(decision?.resolution?.hasPrefix("Changed later:"), true)
    }

    func testCommitmentPicksUpADateNamedLater() {
        var engine = engine()
        let opening = "I'll send the proposal."
        let first = engine.ingest(transcript: opening, elapsed: 10, now: Date())
        XCTAssertNil(first.created.first { $0.kind == .commitment }?.dueDate)
        let changes = engine.ingest(
            transcript: opening + " Let us say Friday.",
            elapsed: 30,
            now: Date()
        )
        let commitment = changes.revised.first { $0.kind == .commitment }
        XCTAssertNotNil(commitment?.dueDate)
        XCTAssertEqual(commitment?.state, .open, "a date does not answer the commitment")
        XCTAssertEqual(commitment?.resolution, "Date named later: Friday")
    }

    func testCoverageNudgeRetiresWhenThePointIsCovered() {
        var engine = engine(points: ["Pricing"])
        let opening = "Let us begin."
        let nudged = engine.ingest(transcript: opening, elapsed: 500, now: Date())
        XCTAssertTrue(nudged.created.contains { $0.kind == .coverage })
        let changes = engine.ingest(
            transcript: opening + " Pricing is agreed at last.",
            elapsed: 520,
            now: Date()
        )
        XCTAssertEqual(changes.revised.first { $0.kind == .coverage }?.state, .resolved)
    }

    func testUnrelatedTalkDoesNotCloseAnything() {
        var engine = engine()
        let opening = "The rollout is blocked on the security review."
        _ = engine.ingest(transcript: opening, elapsed: 10, now: Date())
        let changes = engine.ingest(
            transcript: opening + " The coffee downstairs is good. Someone brought pastries.",
            elapsed: 200,
            now: Date()
        )
        XCTAssertTrue(changes.revised.isEmpty)
    }

    func testAnsweringCannotReviveWhatThePersonDismissed() {
        var engine = engine()
        let opening = "We will get to the migration at some point."
        let created = engine.ingest(transcript: opening, elapsed: 10, now: Date()).created
        guard var clarify = created.first(where: { $0.kind == .clarify }) else {
            return XCTFail("expected a clarify cue")
        }
        clarify.state = .dismissed
        engine.update(clarify)
        let changes = engine.ingest(
            transcript: opening + " Let us do the migration on Friday.",
            elapsed: 40,
            now: Date()
        )
        XCTAssertFalse(changes.revised.contains { $0.id == clarify.id })
    }
}

/// What the person does with a suggestion changes what comes next.
final class MeetingCueFeedbackTests: XCTestCase {
    private func engine(muted: Set<MeetingCue.Kind> = []) -> MeetingCueEngine {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return MeetingCueEngine(plan: MeetingPlan(), calendar: calendar, mutedKinds: muted)
    }

    func testDismissalsStretchTheCooldown() {
        var engine = engine()
        XCTAssertEqual(engine.cooldownMultiplier(for: .figure), 1)
        engine.record(MeetingCueFeedback(kind: .figure, action: .dismissed))
        engine.record(MeetingCueFeedback(kind: .figure, action: .dismissed))
        XCTAssertEqual(engine.cooldownMultiplier(for: .figure), 3)
    }

    func testEnoughDismissalsStopAKindForTheRestOfTheMeeting() {
        var engine = engine()
        _ = engine.ingest(transcript: "It is roughly the same size.", elapsed: 0, now: Date())
        for _ in 0..<MeetingCueEngine.sessionMuteThreshold {
            engine.record(MeetingCueFeedback(kind: .clarify, action: .dismissed))
        }
        XCTAssertTrue(engine.mutedKinds.contains(.clarify))
        let later = engine.ingest(
            transcript: "It is roughly the same size. There were a bunch of requests about it.",
            elapsed: 2_000,
            now: Date()
        )
        XCTAssertFalse(later.created.contains { $0.kind == .clarify })
    }

    func testKeepingSomethingBringsTheKindBack() {
        var engine = engine()
        for _ in 0..<MeetingCueEngine.sessionMuteThreshold {
            engine.record(MeetingCueFeedback(kind: .clarify, action: .dismissed))
        }
        engine.record(MeetingCueFeedback(kind: .clarify, action: .kept))
        XCTAssertFalse(engine.mutedKinds.contains(.clarify))
    }

    func testKindsMutedBeforeTheMeetingAreNeverOffered() {
        var engine = engine(muted: [.figure])
        let created = engine.ingest(
            transcript: "Renewals are sitting at 62 percent right now.",
            elapsed: 10,
            now: Date()
        ).created
        XCTAssertFalse(created.contains { $0.kind == .figure })
    }

    func testTheKindsSomeoneWritesThemselvesAreNeverLearnedFrom() {
        var engine = engine()
        for _ in 0..<5 { engine.record(MeetingCueFeedback(kind: .note, action: .dismissed)) }
        XCTAssertTrue(engine.mutedKinds.isEmpty)
    }
}

final class MeetingCuePreferencesTests: XCTestCase {
    func testAKindIsMutedOnlyAfterRepeatedDismissalsWithNothingKept() {
        var preferences = MeetingCuePreferences()
        for _ in 0..<(MeetingCuePreferences.muteThreshold - 1) {
            preferences.record(MeetingCueFeedback(kind: .figure, action: .dismissed))
        }
        XCTAssertTrue(preferences.mutedKinds.isEmpty)
        preferences.record(MeetingCueFeedback(kind: .figure, action: .dismissed))
        XCTAssertEqual(preferences.mutedKinds, [.figure])
    }

    func testKeepingOneExemptsTheKind() {
        var preferences = MeetingCuePreferences()
        preferences.record(MeetingCueFeedback(kind: .figure, action: .kept))
        for _ in 0..<10 {
            preferences.record(MeetingCueFeedback(kind: .figure, action: .dismissed))
        }
        XCTAssertTrue(preferences.mutedKinds.isEmpty)
    }

    func testTurningAKindBackOnClearsItsTally() {
        var preferences = MeetingCuePreferences()
        for _ in 0..<MeetingCuePreferences.muteThreshold {
            preferences.record(MeetingCueFeedback(kind: .term, action: .dismissed))
        }
        preferences.unmute(.term)
        XCTAssertTrue(preferences.mutedKinds.isEmpty)
        XCTAssertEqual(
            preferences.records[MeetingCue.Kind.term.rawValue],
            MeetingCuePreferences.Record()
        )
    }

    func testNotesTeachNothing() {
        var preferences = MeetingCuePreferences()
        preferences.record(MeetingCueFeedback(kind: .note, action: .dismissed))
        XCTAssertTrue(preferences.records.isEmpty)
    }
}

/// Whose job is it. The same sentence means opposite things depending on who
/// said it, and the recap is only useful if it gets that right.
final class MeetingAttributionTests: XCTestCase {
    private func engine() -> MeetingCueEngine {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return MeetingCueEngine(plan: MeetingPlan(), calendar: calendar)
    }

    private func cue(
        _ transcript: String,
        speaker: MeetingSpeaker,
        kind: MeetingCue.Kind
    ) -> MeetingCue? {
        var engine = engine()
        return engine
            .ingest(transcript: transcript, elapsed: 10, now: Date(), speaker: speaker)
            .created
            .first { $0.kind == kind }
    }

    func testAPromiseYouMakeIsYours() {
        let promise = cue("I'll send the proposal.", speaker: .you, kind: .commitment)
        XCTAssertEqual(promise?.owedBy, .you)
        XCTAssertEqual(promise?.attributionSource, .voice)
        XCTAssertEqual(promise?.label, "You said you would")
    }

    func testAPromiseTheyMakeIsTheirs() {
        let promise = cue("I'll send the proposal.", speaker: .other, kind: .commitment)
        XCTAssertEqual(promise?.owedBy, .other)
        XCTAssertEqual(promise?.attributionSource, .voice)
        XCTAssertEqual(promise?.label, "They said they would")
    }

    func testARequestYouMakeIsOwedByThem() {
        let ask = cue("Can you share the current numbers?", speaker: .you, kind: .request)
        XCTAssertEqual(ask?.owedBy, .other)
        XCTAssertEqual(ask?.label, "You asked them")
    }

    func testARequestMadeOfYouIsYours() {
        let ask = cue("Can you share the current numbers?", speaker: .other, kind: .request)
        XCTAssertEqual(ask?.owedBy, .you)
        XCTAssertEqual(ask?.label, "You were asked")
    }

    func testWithNoVoiceProfileWorkIsAssumedYoursAndSaysSo() {
        let promise = cue("I'll send the proposal.", speaker: .unknown, kind: .commitment)
        XCTAssertEqual(promise?.owedBy, .you)
        XCTAssertEqual(promise?.attributionSource, .assumed)
        let ask = cue("Can you share the current numbers?", speaker: .unknown, kind: .request)
        XCTAssertEqual(ask?.owedBy, .other)
        XCTAssertEqual(ask?.attributionSource, .assumed)
    }

    func testOnlyWorkCarriesAnOwner() {
        let decision = cue("We decided to run the pilot in Leeds.", speaker: .you, kind: .decision)
        XCTAssertEqual(decision?.owedBy, .unknown)
        XCTAssertFalse(decision?.carriesWork ?? true)
    }

    func testTheRuleItself() {
        XCTAssertEqual(
            MeetingCueEngine.attribution(for: .commitment, speaker: .other).owner,
            .other
        )
        XCTAssertEqual(
            MeetingCueEngine.attribution(for: .request, speaker: .other).owner,
            .you
        )
        XCTAssertEqual(
            MeetingCueEngine.attribution(for: .decision, speaker: .you).owner,
            .unknown
        )
    }
}
