import Foundation

/// What the person wants out of this conversation. Written before the meeting,
/// used during it, and repeated in the recap.
struct MeetingPlan: Codable, Equatable, Sendable {
    var kind: MeetingKind
    var title: String
    var goal: String
    var points: [String]

    init(
        kind: MeetingKind = .meeting,
        title: String = "",
        goal: String = "",
        points: [String] = []
    ) {
        self.kind = kind
        self.title = title
        self.goal = goal
        self.points = points
    }

    var cleanedPoints: [String] {
        points
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.defaultTitle : trimmed
    }
}

/// A point from the plan, and whether it has come up yet.
struct MeetingPlanPoint: Identifiable, Equatable, Sendable {
    var text: String
    var covered: Bool

    var id: String { text }
}

/// One complete sentence of transcript, with the UTF-16 range the web contract
/// uses for anchoring.
struct TranscriptSentence: Equatable, Sendable {
    var text: String
    var range: NSRange
    var isQuestion: Bool

    var wordCount: Int {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
    }
}

/// Splits a growing transcript into complete sentences without re-reading what
/// has already been handled.
enum TranscriptScanner {
    static let terminators = CharacterSet(charactersIn: ".?!\n")
    /// Speech output sometimes arrives without punctuation. A run this long is
    /// treated as a sentence so live cues do not stall.
    static let pendingLimit = 320

    static func scan(
        _ text: String,
        from start: Int,
        flushTail: Bool = false
    ) -> (sentences: [TranscriptSentence], consumed: Int) {
        let source = text as NSString
        var cursor = min(max(0, start), source.length)
        var consumed = cursor
        var sentences: [TranscriptSentence] = []

        while cursor < source.length {
            let searchRange = NSRange(location: cursor, length: source.length - cursor)
            let hit = source.rangeOfCharacter(from: terminators, options: [], range: searchRange)
            guard hit.location != NSNotFound else { break }
            let end = NSMaxRange(hit)
            append(&sentences, from: source, range: NSRange(location: cursor, length: end - cursor))
            consumed = end
            cursor = end
        }

        let pending = source.length - consumed
        if pending > 0, flushTail || pending > pendingLimit {
            append(&sentences, from: source, range: NSRange(location: consumed, length: pending))
            consumed = source.length
        }
        return (sentences, consumed)
    }

    private static func append(
        _ sentences: inout [TranscriptSentence],
        from source: NSString,
        range: NSRange
    ) {
        let raw = source.substring(with: range)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 1 else { return }
        let leading = raw.prefix { $0.isWhitespace }.utf16.count
        var trailing = 0
        for character in raw.reversed() {
            guard character.isWhitespace else { break }
            trailing += String(character).utf16.count
        }
        let tightened = NSRange(
            location: range.location + leading,
            length: max(0, range.length - leading - trailing)
        )
        sentences.append(
            TranscriptSentence(
                text: trimmed,
                range: tightened,
                isQuestion: trimmed.hasSuffix("?")
            )
        )
    }
}

/// Turns what was said into what to ask and what to remember.
///
/// Every cue comes from a written rule matched against the words in the
/// transcript. There is no model inference here, nothing is sent anywhere, and
/// each cue keeps the sentence that produced it so the person can judge it.
struct MeetingCueEngine: Sendable {
    private struct PendingQuestion {
        var text: String
        var elapsed: TimeInterval
        var followingSentences: Int
        var followingWords: Int
        var quote: String
    }

    private struct PlanTracker {
        var text: String
        var keywords: [String]
        var matched: Set<String> = []
        var nudged = false

        var threshold: Int { max(1, (keywords.count + 1) / 2) }
        var isCovered: Bool { keywords.isEmpty ? false : matched.count >= threshold }
    }

    /// How long a kind of cue waits before it may fire again.
    private static let cooldowns: [MeetingCue.Kind: TimeInterval] = [
        .ask: 120,
        .unanswered: 0,
        .clarify: 150,
        .commitment: 0,
        .request: 25,
        .deadline: 40,
        .decision: 0,
        .figure: 110,
        .term: 45,
        .risk: 90,
        .coverage: 0,
    ]

    /// How long an unanswered question waits before Sideleaf offers it back.
    static let unansweredGrace: TimeInterval = 45
    /// A reply this short does not count as an answer.
    static let answerWordCount = 12
    /// How often an uncovered plan point may be raised while listening.
    static let coverageInterval: TimeInterval = 420
    static let cueLimit = 200

    private(set) var cues: [MeetingCue] = []
    private var plan: MeetingPlan
    private var trackers: [PlanTracker]
    private var consumed = 0
    private var lastEmission: [MeetingCue.Kind: TimeInterval] = [:]
    private var promptFingerprints: Set<String> = []
    private var quoteFingerprints: Set<String> = []
    private var pendingQuestions: [PendingQuestion] = []
    private var seenTerms: Set<String> = []
    private var lastCoverageNudge: TimeInterval = 0
    private var calendar: Calendar

    init(plan: MeetingPlan = MeetingPlan(), calendar: Calendar = .current) {
        self.plan = plan
        self.calendar = calendar
        trackers = plan.cleanedPoints.map {
            PlanTracker(text: $0, keywords: MeetingCueEngine.keywords(in: $0))
        }
    }

    var meetingPlan: MeetingPlan { plan }

    var planPoints: [MeetingPlanPoint] {
        trackers.map { MeetingPlanPoint(text: $0.text, covered: $0.isCovered) }
    }

    var uncoveredPoints: [String] {
        trackers.filter { !$0.isCovered }.map(\.text)
    }

    /// Reads whatever is new in the transcript and returns only the cues this
    /// call created.
    mutating func ingest(
        transcript: String,
        elapsed: TimeInterval,
        now: Date = Date()
    ) -> [MeetingCue] {
        let scan = TranscriptScanner.scan(transcript, from: consumed)
        consumed = scan.consumed
        var fresh: [MeetingCue] = []
        for sentence in scan.sentences {
            fresh.append(contentsOf: handle(sentence, elapsed: elapsed, now: now))
        }
        fresh.append(contentsOf: expirePendingQuestions(elapsed: elapsed, now: now, atClose: false))
        fresh.append(contentsOf: coverageNudge(elapsed: elapsed, now: now))
        return fresh
    }

    /// Flushes the last partial sentence and everything still waiting.
    mutating func finish(
        transcript: String,
        elapsed: TimeInterval,
        now: Date = Date()
    ) -> [MeetingCue] {
        let scan = TranscriptScanner.scan(transcript, from: consumed, flushTail: true)
        consumed = scan.consumed
        var fresh: [MeetingCue] = []
        for sentence in scan.sentences {
            fresh.append(contentsOf: handle(sentence, elapsed: elapsed, now: now))
        }
        fresh.append(contentsOf: expirePendingQuestions(elapsed: elapsed, now: now, atClose: true))
        for index in trackers.indices where !trackers[index].isCovered && !trackers[index].nudged {
            let point = trackers[index].text
            if let cue = make(
                kind: .coverage,
                prompt: "Not covered: \(point). Send it as a follow-up?",
                quote: "",
                elapsed: elapsed,
                now: now,
                priority: 45,
                ignoreCooldown: true
            ) {
                fresh.append(cue)
            }
        }
        return fresh
    }

    /// Replaces a cue after the person edited, kept or dismissed it.
    mutating func update(_ cue: MeetingCue) {
        guard let index = cues.firstIndex(where: { $0.id == cue.id }) else { return }
        cues[index] = cue
    }

    // MARK: - Detection

    private mutating func handle(
        _ sentence: TranscriptSentence,
        elapsed: TimeInterval,
        now: Date
    ) -> [MeetingCue] {
        trackCoverage(sentence)
        advancePendingQuestions(with: sentence)

        let match = MatchText(sentence.text)
        var fresh: [MeetingCue] = []
        let spoken = MeetingDates.detect(in: match.matchable, now: now, calendar: calendar)

        if sentence.isQuestion, sentence.wordCount >= 4 {
            pendingQuestions.append(
                PendingQuestion(
                    text: sentence.text,
                    elapsed: elapsed,
                    followingSentences: 0,
                    followingWords: 0,
                    quote: sentence.text
                )
            )
        }

        if let cue = rememberCue(sentence, match: match, spoken: spoken, elapsed: elapsed, now: now) {
            fresh.append(cue)
        }
        if let cue = askCue(sentence, match: match, spoken: spoken, elapsed: elapsed, now: now) {
            fresh.append(cue)
        }
        return fresh
    }

    private mutating func rememberCue(
        _ sentence: TranscriptSentence,
        match: MatchText,
        spoken: SpokenDate?,
        elapsed: TimeInterval,
        now: Date
    ) -> MeetingCue? {
        let due = spoken?.date

        if let clause = match.clause(after: Self.decisionMarkers) {
            return make(
                kind: .decision,
                prompt: clause.sentenceCased,
                quote: sentence.text,
                elapsed: elapsed,
                now: now,
                dueDate: due,
                priority: 76
            )
        }
        if !match.contains(any: Self.conditionalMarkers),
           let clause = match.clause(after: Self.commitmentMarkers),
           clause.wordCount >= 2
        {
            return make(
                kind: .commitment,
                prompt: clause.sentenceCased,
                quote: sentence.text,
                elapsed: elapsed,
                now: now,
                dueDate: due,
                priority: 88
            )
        }
        if let clause = match.clause(after: Self.requestMarkers), clause.wordCount >= 2 {
            return make(
                kind: .request,
                prompt: clause.sentenceCased,
                quote: sentence.text,
                elapsed: elapsed,
                now: now,
                dueDate: due,
                priority: 72
            )
        }
        if let spoken, let due, match.contains(any: Self.assessmentMarkers) {
            return make(
                kind: .deadline,
                prompt: "Due \(spoken.phrase): \(sentence.text)",
                quote: sentence.text,
                elapsed: elapsed,
                now: now,
                dueDate: due,
                priority: 74
            )
        }
        if let spoken, let due {
            return make(
                kind: .deadline,
                prompt: "\(spoken.phrase.sentenceCased) was named. What is due then?",
                quote: sentence.text,
                elapsed: elapsed,
                now: now,
                dueDate: due,
                priority: 68
            )
        }
        return nil
    }

    private mutating func askCue(
        _ sentence: TranscriptSentence,
        match: MatchText,
        spoken: SpokenDate?,
        elapsed: TimeInterval,
        now: Date
    ) -> MeetingCue? {
        if let marker = match.firstMatch(in: Self.riskMarkers) {
            return make(
                kind: .risk,
                prompt: Self.riskQuestion(for: marker),
                quote: sentence.text,
                elapsed: elapsed,
                now: now,
                priority: 78
            )
        }
        if let spoken, spoken.isVague {
            return make(
                kind: .clarify,
                prompt: "Can we put a date on \"\(spoken.phrase)\"?",
                quote: sentence.text,
                elapsed: elapsed,
                now: now,
                priority: 66
            )
        }
        if match.contains(any: Self.assessmentMarkers), spoken == nil {
            return make(
                kind: .ask,
                prompt: "When exactly is that due?",
                quote: sentence.text,
                elapsed: elapsed,
                now: now,
                priority: 64
            )
        }
        if match.contains(any: Self.deferralMarkers) {
            return make(
                kind: .ask,
                prompt: "When can we come back to that?",
                quote: sentence.text,
                elapsed: elapsed,
                now: now,
                priority: 62
            )
        }
        if let term = unexplainedTerm(in: sentence.text) {
            seenTerms.insert(term)
            return make(
                kind: .term,
                prompt: "What does \(term) stand for here?",
                quote: sentence.text,
                elapsed: elapsed,
                now: now,
                priority: 56
            )
        }
        if let figure = figurePhrase(in: sentence.text, excluding: spoken?.phrase) {
            return make(
                kind: .figure,
                prompt: "Can I read that back — \(figure)?",
                quote: sentence.text,
                elapsed: elapsed,
                now: now,
                priority: 54
            )
        }
        if let marker = match.firstMatch(in: Self.quantityHedges) {
            return make(
                kind: .clarify,
                prompt: "Can we put a number on \"\(marker.trimmingCharacters(in: .whitespaces))\"?",
                quote: sentence.text,
                elapsed: elapsed,
                now: now,
                priority: 52
            )
        }
        if match.contains(any: Self.certaintyHedges) {
            return make(
                kind: .clarify,
                prompt: "What would it take to know that for certain?",
                quote: sentence.text,
                elapsed: elapsed,
                now: now,
                priority: 50
            )
        }
        return nil
    }

    // MARK: - Unanswered questions

    private mutating func advancePendingQuestions(with sentence: TranscriptSentence) {
        guard !pendingQuestions.isEmpty else { return }
        for index in pendingQuestions.indices where pendingQuestions[index].quote != sentence.text {
            pendingQuestions[index].followingSentences += 1
            if !sentence.isQuestion, !MatchText(sentence.text).contains(any: Self.nonAnswers) {
                pendingQuestions[index].followingWords += sentence.wordCount
            }
        }
    }

    private mutating func expirePendingQuestions(
        elapsed: TimeInterval,
        now: Date,
        atClose: Bool
    ) -> [MeetingCue] {
        var fresh: [MeetingCue] = []
        var retained: [PendingQuestion] = []
        for question in pendingQuestions {
            let answered = question.followingWords >= Self.answerWordCount
            let matured = question.followingSentences >= 2
                || elapsed - question.elapsed >= Self.unansweredGrace
            if answered {
                continue
            }
            guard matured || atClose else {
                retained.append(question)
                continue
            }
            if let cue = make(
                kind: .unanswered,
                prompt: question.text,
                quote: question.quote,
                elapsed: elapsed,
                now: now,
                priority: 84,
                ignoreCooldown: true
            ) {
                fresh.append(cue)
            }
        }
        pendingQuestions = retained
        return fresh
    }

    // MARK: - Plan coverage

    private mutating func trackCoverage(_ sentence: TranscriptSentence) {
        guard !trackers.isEmpty else { return }
        let words = Set(Self.keywords(in: sentence.text))
        guard !words.isEmpty else { return }
        for index in trackers.indices where !trackers[index].isCovered {
            for keyword in trackers[index].keywords where words.contains(keyword) {
                trackers[index].matched.insert(keyword)
            }
        }
    }

    private mutating func coverageNudge(elapsed: TimeInterval, now: Date) -> [MeetingCue] {
        guard elapsed - lastCoverageNudge >= Self.coverageInterval else { return [] }
        guard let index = trackers.firstIndex(where: { !$0.isCovered && !$0.nudged })
        else { return [] }
        trackers[index].nudged = true
        lastCoverageNudge = elapsed
        guard let cue = make(
            kind: .coverage,
            prompt: "We have not covered \(trackers[index].text) yet. Bring it up?",
            quote: "",
            elapsed: elapsed,
            now: now,
            priority: 70,
            ignoreCooldown: true
        ) else { return [] }
        return [cue]
    }

    // MARK: - Cue construction

    private mutating func make(
        kind: MeetingCue.Kind,
        prompt: String,
        quote: String,
        elapsed: TimeInterval,
        now: Date,
        dueDate: Date? = nil,
        priority: Int,
        ignoreCooldown: Bool = false
    ) -> MeetingCue? {
        guard cues.count < Self.cueLimit else { return nil }
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 3 else { return nil }
        let fingerprint = Self.fingerprint(text)
        guard !promptFingerprints.contains(fingerprint) else { return nil }
        if !quote.isEmpty {
            let quoteKey = "\(kind.rawValue)|\(Self.fingerprint(quote))"
            guard !quoteFingerprints.contains(quoteKey) else { return nil }
            quoteFingerprints.insert(quoteKey)
        }
        if !ignoreCooldown, let last = lastEmission[kind] {
            let cooldown = Self.cooldowns[kind] ?? 60
            guard elapsed - last >= cooldown else { return nil }
        }
        promptFingerprints.insert(fingerprint)
        lastEmission[kind] = elapsed
        let cue = MeetingCue(
            kind: kind,
            prompt: text,
            quote: quote,
            createdAt: now,
            offset: elapsed,
            dueDate: dueDate,
            priority: priority
        )
        cues.append(cue)
        return cue
    }

    private func unexplainedTerm(in sentence: String) -> String? {
        for token in sentence.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            let cleaned = token.trimmingCharacters(
                in: CharacterSet.alphanumerics.inverted
            )
            guard cleaned.count >= 2, cleaned.count <= 6 else { continue }
            guard cleaned.allSatisfy({ $0.isUppercase && $0.isLetter }) else { continue }
            guard !Self.knownAcronyms.contains(cleaned) else { continue }
            guard !seenTerms.contains(cleaned) else { continue }
            return cleaned
        }
        return nil
    }

    private func figurePhrase(in sentence: String, excluding spokenPhrase: String?) -> String? {
        let tokens = sentence.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        for (index, token) in tokens.enumerated() {
            let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: ",.!?;:\""))
            guard cleaned.contains(where: \.isNumber) else { continue }
            let lowered = cleaned.lowercased()
            guard !lowered.hasSuffix("am"), !lowered.hasSuffix("pm") else { continue }
            guard !lowered.hasSuffix("st"), !lowered.hasSuffix("nd"),
                  !lowered.hasSuffix("rd"), !lowered.hasSuffix("th")
            else { continue }
            if let spokenPhrase, spokenPhrase.lowercased().contains(lowered) { continue }
            var phrase = cleaned
            if index + 1 < tokens.count {
                let next = tokens[index + 1]
                    .trimmingCharacters(in: CharacterSet(charactersIn: ",.!?;:\""))
                    .lowercased()
                if Self.figureUnits.contains(next) { phrase += " " + next }
            }
            return phrase
        }
        return nil
    }

    private static func riskQuestion(for marker: String) -> String {
        let trimmed = marker.trimmingCharacters(in: .whitespaces)
        if trimmed.contains("block") { return "What would it take to unblock that?" }
        if trimmed.contains("behind") || trimmed.contains("slip") {
            return "What does that do to the date?"
        }
        if trimmed.contains("risk") || trimmed.contains("worried")
            || trimmed.contains("concerned")
        {
            return "What is the worst case there, and who owns it?"
        }
        return "What would it take to fix that?"
    }

    static func keywords(in text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 4 && !stopWords.contains($0) }
    }

    static func fingerprint(_ text: String) -> String {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }

    // MARK: - Phrase tables

    private static let commitmentMarkers = [
        "i'm going to ", "i am going to ", "i'm gonna ", "we're going to ",
        "we are going to ", "we're gonna ", "i'll go ahead and ", "i'll make sure ",
        "i'll ", "i will ", "we'll ", "we will ", "let me ", "i can ",
        "i'd be happy to ", "i would be happy to ",
    ]

    private static let conditionalMarkers = ["if i ", "if we ", "unless "]

    private static let requestMarkers = [
        "can you ", "could you ", "would you ", "will you ", "you need to ",
        "we need to ", "you should ", "someone needs to ", "make sure you ",
        "don't forget to ", "remember to ", "it would help if you ",
    ]

    private static let decisionMarkers = [
        "we've decided to ", "we have decided to ", "we decided to ", "we've decided ",
        "we have decided ", "we decided ", "we've agreed to ", "we agreed to ",
        "we've agreed ", "we agreed ", "let's go with ", "we're going with ",
        "we are going with ", "we'll go with ", "the decision is ", "we settled on ",
        "we're moving forward with ",
    ]

    private static let riskMarkers = [
        "blocked", "blocker", "at risk", "the risk is", "risk of", "concerned about",
        "worried about", "the problem is", "the issue is", "bottleneck",
        "behind schedule", "slipping", "won't be able to", "running out of",
        "short on", "falling behind",
    ]

    private static let deferralMarkers = [
        "take that offline", "come back to that", "circle back", "park that",
        "another time", "follow up on that", "discuss that later", "off the top of my head",
    ]

    private static let assessmentMarkers = [
        " due ", " exam", " midterm", " final exam", " assignment", " quiz",
        " graded", " submit ", " deadline", " hand in ",
    ]

    private static let quantityHedges = [
        " a bunch ", " a few ", " a couple ", " roughly ", " ballpark ",
        " more or less ", " give or take ", " a lot of ", " a handful ",
    ]

    private static let certaintyHedges = [
        " not sure ", " i guess ", " we'll see ", " kind of ", " sort of ",
        " it depends ", " somehow ", " i think so ", " probably ", " maybe ",
    ]

    private static let nonAnswers = [
        " not sure ", " i don't know ", " i dont know ", " good question ",
        " let me check ", " i'd have to check ", " we'll see ", " no idea ",
    ]

    private static let figureUnits: Set<String> = [
        "percent", "%", "k", "m", "million", "billion", "thousand", "dollars",
        "euros", "pounds", "hours", "hour", "days", "day", "weeks", "week",
        "months", "month", "people", "users", "seats", "licences", "licenses",
    ]

    private static let knownAcronyms: Set<String> = [
        "I", "A", "OK", "AM", "PM", "TV", "US", "USA", "UK", "EU", "CEO", "CTO",
        "CFO", "COO", "HR", "IT", "AI", "PDF", "URL", "FAQ", "ID", "TBD", "ASAP",
        "RSVP", "Q1", "Q2", "Q3", "Q4", "FYI", "EOD", "EOW", "VP", "PM's", "APP",
    ]

    private static let stopWords: Set<String> = [
        "about", "after", "again", "also", "and", "another", "any", "because",
        "been", "before", "being", "between", "both", "each", "from", "have",
        "here", "into", "just", "like", "more", "most", "much", "only", "other",
        "over", "same", "should", "some", "such", "than", "that", "their",
        "them", "then", "there", "these", "they", "this", "those", "through",
        "very", "were", "what", "when", "where", "which", "while", "will",
        "with", "would", "your", "ours", "theirs",
    ]
}

/// A sentence prepared for matching: lowercased, apostrophes normalised, and
/// padded so phrase lookups cannot match inside a longer word.
struct MatchText: Sendable {
    /// Punctuation is swapped for spaces one character at a time, so a phrase
    /// at the end of a sentence still matches and every offset still lines up
    /// with the original words.
    private static let punctuation: Set<Character> = [".", ",", ";", ":", "!", "?", "\"", "(", ")"]

    let original: String
    let lowered: String
    /// Lowercased with punctuation blanked out, for phrase lookups.
    let matchable: String
    let padded: String
    /// True when lowercasing preserved UTF-16 offsets, so clauses can be sliced
    /// out of the original text with its capitalisation intact.
    let offsetsAlign: Bool

    init(_ sentence: String) {
        let normalised = sentence
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\n", with: " ")
        original = normalised
        lowered = normalised.lowercased()
        matchable = String(lowered.map { Self.punctuation.contains($0) ? " " : $0 })
        padded = " " + matchable + " "
        offsetsAlign = lowered.utf16.count == normalised.utf16.count
    }

    func contains(any phrases: [String]) -> Bool {
        firstMatch(in: phrases) != nil
    }

    func firstMatch(in phrases: [String]) -> String? {
        phrases.first { padded.contains($0) }
    }

    /// Returns the rest of the sentence after the first marker that matches.
    func clause(after markers: [String]) -> Clause? {
        let source = padded as NSString
        for marker in markers {
            let hit = source.range(of: marker)
            guard hit.location != NSNotFound else { continue }
            // `padded` adds one leading space, so shift back into sentence space.
            let start = max(0, NSMaxRange(hit) - 1)
            let text = offsetsAlign ? original : lowered
            let body = text as NSString
            guard start < body.length else { continue }
            let remainder = body.substring(from: start)
            return Clause(remainder)
        }
        return nil
    }
}

/// The part of a sentence that follows a marker, tidied into something a person
/// would want to read back later.
struct Clause: Sendable {
    let text: String

    init(_ raw: String) {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for filler in ["just ", "also ", "probably ", "definitely ", "go ahead and ", "then "]
        where value.lowercased().hasPrefix(filler) {
            value = String(value.dropFirst(filler.count))
        }
        while let last = value.last,
              last == "." || last == "," || last == ";" || last == "!" || last == "?"
        {
            value = String(value.dropLast())
        }
        if value.utf16.count > 180 {
            let cut = value.prefix(180)
            if let boundary = cut.lastIndex(of: " ") {
                value = String(cut[..<boundary]) + "…"
            } else {
                value = String(cut) + "…"
            }
        }
        text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var wordCount: Int { text.split(separator: " ").count }

    var sentenceCased: String { text.sentenceCased }
}

extension String {
    /// Capitalises only the first character, leaving names and acronyms alone.
    var sentenceCased: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
