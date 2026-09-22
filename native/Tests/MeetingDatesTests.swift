import Foundation
import XCTest
@testable import Sideleaf

final class MeetingDatesTests: XCTestCase {
    /// Tuesday 22 September 2026, 10:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_790_071_200)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func resolved(_ sentence: String) -> String? {
        guard let spoken = MeetingDates.detect(in: sentence, now: now, calendar: calendar),
              let date = spoken.date
        else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    func testFixtureIsTheTuesdayTheseTestsAssume() {
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day, .weekday], from: now),
            DateComponents(year: 2026, month: 9, day: 22, weekday: 3)
        )
    }

    func testTomorrowResolvesToTheNextMorning() {
        XCTAssertEqual(resolved("i will send it tomorrow"), "2026-09-23 09:00")
    }

    func testNamedWeekdayResolvesForward() {
        XCTAssertEqual(resolved("let us review it by friday"), "2026-09-25 09:00")
    }

    func testNextWeekdaySkipsTheCurrentWeek() {
        XCTAssertEqual(resolved("let us review it next friday"), "2026-10-02 09:00")
    }

    func testEndOfWeekResolvesToFridayAfternoon() {
        XCTAssertEqual(resolved("i need it by end of the week"), "2026-09-25 17:00")
    }

    func testEndOfMonthResolvesToTheLastDay() {
        XCTAssertEqual(resolved("the invoice goes out end of the month"), "2026-09-30 17:00")
    }

    func testRelativeWeeksAreCounted() {
        XCTAssertEqual(resolved("we will pick this up in two weeks"), "2026-10-06 09:00")
    }

    func testSpokenTimeOverridesTheDefaultHour() {
        XCTAssertEqual(resolved("shall we meet tomorrow at 3pm"), "2026-09-23 15:00")
    }

    func testDayOfMonthRollsToTheNextMonthWhenItHasPassed() {
        XCTAssertEqual(resolved("the board meets on the 14th"), "2026-10-14 09:00")
    }

    func testCalendarDateRollsToTheNextYearWhenItHasPassed() {
        XCTAssertEqual(resolved("the contract ends march 3"), "2027-03-03 09:00")
    }

    func testVaguePhrasesAreFlaggedWithoutADate() {
        let spoken = MeetingDates.detect(in: "we will get to it soon", now: now, calendar: calendar)
        XCTAssertEqual(spoken?.phrase, "soon")
        XCTAssertNil(spoken?.date)
        XCTAssertEqual(spoken?.isVague, true)
    }

    func testSentencesWithoutDatesReturnNothing() {
        XCTAssertNil(MeetingDates.detect(in: "that sounds good to me", now: now, calendar: calendar))
    }

    func testMayIsOnlyAMonthWhenADayFollows() {
        XCTAssertNil(MeetingDates.detect(in: "we may be able to help", now: now, calendar: calendar))
        XCTAssertEqual(resolved("the deadline is may 4"), "2027-05-04 09:00")
    }
}
