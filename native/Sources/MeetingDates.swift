import Foundation

/// A date or time that was named out loud.
struct SpokenDate: Equatable, Sendable {
    /// The words that were matched, in the order they were said.
    var phrase: String
    /// The instant those words resolve to, when they resolve at all.
    var date: Date?
    /// True when the phrase names a time without naming a day.
    var isVague: Bool
}

/// Resolves the small set of date expressions people actually say in meetings.
///
/// Every rule here is explicit and reversible: the phrase that matched is kept
/// alongside the instant it produced, so a person can see why Sideleaf offered
/// a particular reminder. No expression is guessed at; an unmatched sentence
/// returns nothing.
enum MeetingDates {
    /// The hour a bare day resolves to when no time was said.
    static let defaultHour = 9
    /// The hour "end of" phrases resolve to.
    static let endOfDayHour = 17

    private static let weekdays: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
        "thursday": 5, "friday": 6, "saturday": 7,
    ]

    private static let months: [String: Int] = [
        "january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6,
        "july": 7, "august": 8, "september": 9, "october": 10, "november": 11,
        "december": 12, "jan": 1, "feb": 2, "mar": 3, "apr": 4, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "sept": 9, "oct": 10, "nov": 11, "dec": 12,
    ]

    private static let numberWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11,
        "twelve": 12, "fourteen": 14, "thirty": 30,
    ]

    /// Phrases that promise a time without naming one.
    static let vaguePhrases = [
        "soon", "shortly", "eventually", "at some point", "some point",
        "down the road", "in a bit", "later on", "later today", "sometime",
        "asap", "as soon as possible", "tbd", "to be determined",
        "in the next few days", "in a few days", "in the coming weeks",
    ]

    /// Finds the first date expression in a sentence that has already been
    /// lowercased and had its typographic apostrophes normalized.
    static func detect(
        in sentence: String,
        now: Date,
        calendar: Calendar = .current
    ) -> SpokenDate? {
        let padded = " " + sentence + " "
        if let resolved = concrete(in: padded, now: now, calendar: calendar) {
            return resolved
        }
        for phrase in vaguePhrases where padded.contains(" " + phrase + " ")
            || padded.contains(" " + phrase + ",") || padded.contains(" " + phrase + ".")
        {
            return SpokenDate(phrase: phrase, date: nil, isVague: true)
        }
        return nil
    }

    private static func concrete(
        in padded: String,
        now: Date,
        calendar: Calendar
    ) -> SpokenDate? {
        let time = spokenTime(in: padded)
        func stamp(_ day: Date, hour: Int) -> Date {
            apply(time: time, to: day, defaultHour: hour, calendar: calendar)
        }

        if padded.contains(" end of the day ") || padded.contains(" eod ")
            || padded.contains(" by end of day ") || padded.contains(" end of day ")
        {
            return SpokenDate(
                phrase: "end of the day",
                date: stamp(startOfDay(now, calendar), hour: endOfDayHour),
                isVague: false
            )
        }
        if padded.contains(" end of the week ") || padded.contains(" end of this week ")
            || padded.contains(" eow ") || padded.contains(" end of week ")
        {
            let friday = nextWeekday(6, onOrAfter: startOfDay(now, calendar), calendar: calendar)
            return SpokenDate(
                phrase: "end of the week",
                date: stamp(friday, hour: endOfDayHour),
                isVague: false
            )
        }
        if padded.contains(" end of the month ") || padded.contains(" end of this month ")
            || padded.contains(" eom ")
        {
            return SpokenDate(
                phrase: "end of the month",
                date: stamp(endOfMonth(now, calendar), hour: endOfDayHour),
                isVague: false
            )
        }
        if padded.contains(" end of the quarter ") || padded.contains(" end of this quarter ") {
            return SpokenDate(
                phrase: "end of the quarter",
                date: stamp(endOfQuarter(now, calendar), hour: endOfDayHour),
                isVague: false
            )
        }
        if padded.contains(" first thing tomorrow ") {
            let day = calendar.date(byAdding: .day, value: 1, to: startOfDay(now, calendar))
            return SpokenDate(
                phrase: "first thing tomorrow",
                date: day.map { stamp($0, hour: 8) },
                isVague: false
            )
        }
        if padded.contains(" tomorrow ") || padded.contains(" tomorrow.") {
            let day = calendar.date(byAdding: .day, value: 1, to: startOfDay(now, calendar))
            return SpokenDate(
                phrase: "tomorrow",
                date: day.map { stamp($0, hour: defaultHour) },
                isVague: false
            )
        }
        if padded.contains(" tonight ") {
            return SpokenDate(
                phrase: "tonight",
                date: stamp(startOfDay(now, calendar), hour: 19),
                isVague: false
            )
        }
        if padded.contains(" this afternoon ") {
            return SpokenDate(
                phrase: "this afternoon",
                date: stamp(startOfDay(now, calendar), hour: 15),
                isVague: false
            )
        }
        if padded.contains(" this morning ") {
            return SpokenDate(
                phrase: "this morning",
                date: stamp(startOfDay(now, calendar), hour: 10),
                isVague: false
            )
        }
        if padded.contains(" today ") || padded.contains(" by today ") {
            let base = startOfDay(now, calendar)
            let resolved = stamp(base, hour: endOfDayHour)
            return SpokenDate(
                phrase: "today",
                date: resolved > now ? resolved : now.addingTimeInterval(3600),
                isVague: false
            )
        }
        if padded.contains(" next week ") {
            let day = calendar.date(byAdding: .day, value: 7, to: startOfDay(now, calendar))
            return SpokenDate(
                phrase: "next week",
                date: day.map { stamp($0, hour: defaultHour) },
                isVague: false
            )
        }
        if padded.contains(" next month ") {
            let day = calendar.date(byAdding: .month, value: 1, to: startOfDay(now, calendar))
            return SpokenDate(
                phrase: "next month",
                date: day.map { stamp($0, hour: defaultHour) },
                isVague: false
            )
        }
        if let relative = relativeOffset(in: padded, now: now, calendar: calendar, time: time) {
            return relative
        }
        for (name, weekday) in weekdays.sorted(by: { $0.key < $1.key }) {
            guard padded.contains(" " + name + " ") || padded.contains(" " + name + ",")
                || padded.contains(" " + name + ".")
            else { continue }
            let isNext = padded.contains(" next " + name + " ")
            let start = isNext
                ? startOfNextWeek(now, calendar)
                : startOfDay(now, calendar)
            let day = nextWeekday(weekday, onOrAfter: start, calendar: calendar)
            return SpokenDate(
                phrase: isNext ? "next " + name : name,
                date: stamp(day, hour: defaultHour),
                isVague: false
            )
        }
        if let calendarDate = monthAndDay(in: padded, now: now, calendar: calendar, time: time) {
            return calendarDate
        }
        return nil
    }

    /// "in three days", "in a couple of weeks", "in 2 months".
    private static func relativeOffset(
        in padded: String,
        now: Date,
        calendar: Calendar,
        time: DateComponents?
    ) -> SpokenDate? {
        let units: [(String, Calendar.Component)] = [
            ("days", .day), ("day", .day), ("weeks", .weekOfYear), ("week", .weekOfYear),
            ("months", .month), ("month", .month),
        ]
        let words = padded
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",.!?")) }
        for index in words.indices where words[index] == "in" {
            var cursor = index + 1
            var amount: Int?
            var spoken: [String] = ["in"]
            while cursor < words.count, cursor <= index + 3 {
                let word = words[cursor]
                if word == "couple" || word == "few" {
                    amount = word == "couple" ? 2 : 3
                    spoken.append(word)
                    cursor += 1
                    continue
                }
                if word == "of" || word == "the" || word == "next" {
                    spoken.append(word)
                    cursor += 1
                    continue
                }
                if let value = Int(word) ?? numberWords[word] {
                    amount = value
                    spoken.append(word)
                    cursor += 1
                    continue
                }
                guard let unit = units.first(where: { $0.0 == word }),
                      let amount, amount > 0, amount <= 52
                else { break }
                spoken.append(word)
                let day = calendar.date(
                    byAdding: unit.1,
                    value: amount,
                    to: startOfDay(now, calendar)
                )
                return SpokenDate(
                    phrase: spoken.joined(separator: " "),
                    date: day.map {
                        apply(time: time, to: $0, defaultHour: defaultHour, calendar: calendar)
                    },
                    isVague: false
                )
            }
        }
        return nil
    }

    /// "march 3", "on the 14th", "june 2nd".
    private static func monthAndDay(
        in padded: String,
        now: Date,
        calendar: Calendar,
        time: DateComponents?
    ) -> SpokenDate? {
        let words = padded
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",.!?")) }
        for (index, word) in words.enumerated() {
            guard let month = months[word] else { continue }
            let dayWord = index + 1 < words.count ? words[index + 1] : ""
            guard let day = dayNumber(dayWord) else { continue }
            var components = calendar.dateComponents([.year], from: now)
            components.month = month
            components.day = day
            components.hour = time?.hour ?? defaultHour
            components.minute = time?.minute ?? 0
            guard var resolved = calendar.date(from: components) else { continue }
            if resolved < now, let nextYear = calendar.date(byAdding: .year, value: 1, to: resolved) {
                resolved = nextYear
            }
            return SpokenDate(phrase: "\(word) \(dayWord)", date: resolved, isVague: false)
        }
        for (index, word) in words.enumerated() where word == "the" {
            let dayWord = index + 1 < words.count ? words[index + 1] : ""
            guard dayWord.hasSuffix("st") || dayWord.hasSuffix("nd") || dayWord.hasSuffix("rd")
                || dayWord.hasSuffix("th"),
                let day = dayNumber(dayWord)
            else { continue }
            var components = calendar.dateComponents([.year, .month], from: now)
            components.day = day
            components.hour = time?.hour ?? defaultHour
            components.minute = time?.minute ?? 0
            guard var resolved = calendar.date(from: components) else { continue }
            if resolved < now,
               let nextMonth = calendar.date(byAdding: .month, value: 1, to: resolved)
            {
                resolved = nextMonth
            }
            return SpokenDate(phrase: "the \(dayWord)", date: resolved, isVague: false)
        }
        return nil
    }

    private static func dayNumber(_ word: String) -> Int? {
        let digits = word.prefix { $0.isNumber }
        guard let value = Int(digits), (1...31).contains(value) else { return nil }
        return value
    }

    /// "at 3", "3pm", "at 10:30".
    private static func spokenTime(in padded: String) -> DateComponents? {
        let words = padded
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",.!?")) }
        for (index, word) in words.enumerated() {
            var token = word
            var meridiem: String?
            for suffix in ["am", "pm"] where token.hasSuffix(suffix) && token.count > suffix.count {
                meridiem = suffix
                token = String(token.dropLast(suffix.count))
            }
            if meridiem == nil, index + 1 < words.count, ["am", "pm"].contains(words[index + 1]) {
                meridiem = words[index + 1]
            }
            let parts = token.split(separator: ":").map(String.init)
            guard let hourText = parts.first, let hour = Int(hourText), (0...23).contains(hour)
            else { continue }
            let minute = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            guard (0...59).contains(minute) else { continue }
            let precededByAt = index > 0 && words[index - 1] == "at"
            guard meridiem != nil || precededByAt else { continue }
            var resolvedHour = hour
            if meridiem == "pm", hour < 12 { resolvedHour += 12 }
            if meridiem == "am", hour == 12 { resolvedHour = 0 }
            if meridiem == nil, hour <= 6 { resolvedHour += 12 }
            return DateComponents(hour: resolvedHour, minute: minute)
        }
        return nil
    }

    private static func apply(
        time: DateComponents?,
        to day: Date,
        defaultHour: Int,
        calendar: Calendar
    ) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = time?.hour ?? defaultHour
        components.minute = time?.minute ?? 0
        return calendar.date(from: components) ?? day
    }

    private static func startOfDay(_ date: Date, _ calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }

    private static func startOfNextWeek(_ date: Date, _ calendar: Calendar) -> Date {
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)
        return interval?.end
            ?? calendar.date(byAdding: .day, value: 7, to: startOfDay(date, calendar))
            ?? date
    }

    private static func nextWeekday(
        _ weekday: Int,
        onOrAfter start: Date,
        calendar: Calendar
    ) -> Date {
        if calendar.component(.weekday, from: start) == weekday { return start }
        return calendar.nextDate(
            after: start,
            matching: DateComponents(weekday: weekday),
            matchingPolicy: .nextTime
        ) ?? start
    }

    private static func endOfMonth(_ date: Date, _ calendar: Calendar) -> Date {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return date }
        return calendar.date(byAdding: .day, value: -1, to: interval.end) ?? date
    }

    private static func endOfQuarter(_ date: Date, _ calendar: Calendar) -> Date {
        let month = calendar.component(.month, from: date)
        let finalMonth = ((month - 1) / 3 + 1) * 3
        var components = calendar.dateComponents([.year], from: date)
        components.month = finalMonth
        components.day = 1
        guard let firstOfFinalMonth = calendar.date(from: components) else { return date }
        return endOfMonth(firstOfFinalMonth, calendar)
    }
}
