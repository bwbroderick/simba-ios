import XCTest
@testable import Simba

final class TimestampTests: XCTestCase {

    // MARK: - relativeTimestamp

    func test_lessThan60Seconds_returnsNow() {
        let date = Date(timeIntervalSinceNow: -30)
        let header = rfc2822(from: date)
        XCTAssertEqual(GmailViewModel.relativeTimestamp(from: header), "Now")
    }

    func test_5MinutesAgo_returns5m() {
        let date = Date(timeIntervalSinceNow: -(5 * 60))
        let header = rfc2822(from: date)
        XCTAssertEqual(GmailViewModel.relativeTimestamp(from: header), "5m")
    }

    func test_3HoursAgo_returns3h() {
        let date = Date(timeIntervalSinceNow: -(3 * 60 * 60))
        let header = rfc2822(from: date)
        XCTAssertEqual(GmailViewModel.relativeTimestamp(from: header), "3h")
    }

    func test_2DaysAgo_returns2d() {
        let date = Date(timeIntervalSinceNow: -(2 * 24 * 60 * 60))
        let header = rfc2822(from: date)
        XCTAssertEqual(GmailViewModel.relativeTimestamp(from: header), "2d")
    }

    // MARK: - parseDate formats

    func test_parseDate_withDayOfWeekAndSeconds() {
        let result = GmailViewModel.parseDate(from: "Mon, 01 Jan 2024 12:00:00 +0000")
        XCTAssertNotNil(result)
    }

    func test_parseDate_withoutDayOfWeek() {
        let result = GmailViewModel.parseDate(from: "01 Jan 2024 12:00:00 +0000")
        XCTAssertNotNil(result)
    }

    func test_parseDate_withoutSeconds() {
        let result = GmailViewModel.parseDate(from: "Mon, 01 Jan 2024 12:00 +0000")
        XCTAssertNotNil(result)
    }

    func test_parseDate_withParentheticalTimezone() {
        let result = GmailViewModel.parseDate(from: "Mon, 01 Jan 2024 12:00:00 +0000 (UTC)")
        XCTAssertNotNil(result)
    }

    func test_parseDate_invalidString_returnsNil() {
        let result = GmailViewModel.parseDate(from: "not a date")
        XCTAssertNil(result)
    }

    // MARK: - Helpers

    private func rfc2822(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }
}
