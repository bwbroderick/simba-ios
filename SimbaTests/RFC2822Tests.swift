import XCTest
@testable import Simba

final class RFC2822Tests: XCTestCase {

    func test_noCcNoBcc_headersInCorrectOrder() {
        let raw = GmailViewModel.buildRawMessage(to: "a@b.com", subject: "Hello", body: "Body text")
        let lines = raw.components(separatedBy: "\r\n")
        XCTAssertEqual(lines[0], "To: a@b.com")
        XCTAssertEqual(lines[1], "Subject: Hello")
        XCTAssertEqual(lines[2], "Content-Type: text/plain; charset=\"UTF-8\"")
        XCTAssertFalse(raw.contains("Cc:"))
        XCTAssertFalse(raw.contains("Bcc:"))
    }

    func test_headerBodySeparatedByBlankLine() {
        let raw = GmailViewModel.buildRawMessage(to: "a@b.com", subject: "Hello", body: "Body text")
        XCTAssertTrue(raw.contains("\r\n\r\n"))
        let parts = raw.components(separatedBy: "\r\n\r\n")
        XCTAssertEqual(parts.last, "Body text")
    }

    func test_ccOnly_insertedAtCorrectIndex() {
        let raw = GmailViewModel.buildRawMessage(to: "a@b.com", subject: "Hello", body: "Body", cc: "cc@b.com")
        let lines = raw.components(separatedBy: "\r\n")
        XCTAssertEqual(lines[0], "To: a@b.com")
        XCTAssertEqual(lines[1], "Cc: cc@b.com")
        XCTAssertEqual(lines[2], "Subject: Hello")
        XCTAssertFalse(raw.contains("Bcc:"))
    }

    func test_bccOnly_insertedAtCorrectIndex() {
        let raw = GmailViewModel.buildRawMessage(to: "a@b.com", subject: "Hello", body: "Body", bcc: "bcc@b.com")
        let lines = raw.components(separatedBy: "\r\n")
        XCTAssertEqual(lines[0], "To: a@b.com")
        XCTAssertEqual(lines[1], "Bcc: bcc@b.com")
        XCTAssertEqual(lines[2], "Subject: Hello")
        XCTAssertFalse(raw.contains("Cc:"))
    }

    func test_ccAndBcc_bothPresent() {
        let raw = GmailViewModel.buildRawMessage(to: "a@b.com", subject: "Hello", body: "Body",
                                                  cc: "cc@b.com", bcc: "bcc@b.com")
        XCTAssertTrue(raw.contains("Cc: cc@b.com"))
        XCTAssertTrue(raw.contains("Bcc: bcc@b.com"))
    }

    func test_whitespaceCc_ignored() {
        let raw = GmailViewModel.buildRawMessage(to: "a@b.com", subject: "Hello", body: "Body", cc: "   ")
        XCTAssertFalse(raw.contains("Cc:"))
    }

    func test_crlfSeparators() {
        let raw = GmailViewModel.buildRawMessage(to: "a@b.com", subject: "Hello", body: "Body")
        XCTAssertTrue(raw.contains("\r\n"))
        XCTAssertFalse(raw.components(separatedBy: "\r\n").isEmpty)
    }
}
