import XCTest
@testable import Simba

final class CacheSerializationTests: XCTestCase {

    func test_fullRoundTrip_encodesAndDecodesCorrectly() throws {
        let thread = EmailThread(
            threadID: "abc123",
            sender: Sender(name: "Alice", email: "alice@example.com", initials: "AL"),
            subject: "Test Subject",
            pages: ["Page one.", "Page two."],
            htmlBody: "<p>Hello</p>",
            isUnread: true,
            isStarred: true,
            messageCount: 3,
            timestamp: "2h",
            labelIds: ["INBOX", "STARRED"]
        )

        let cached = CachedThread(from: thread)
        let data = try JSONEncoder().encode(cached)
        let decoded = try JSONDecoder().decode(CachedThread.self, from: data)

        XCTAssertEqual(decoded.threadID, "abc123")
        XCTAssertEqual(decoded.senderName, "Alice")
        XCTAssertEqual(decoded.senderEmail, "alice@example.com")
        XCTAssertEqual(decoded.senderInitials, "AL")
        XCTAssertEqual(decoded.subject, "Test Subject")
        XCTAssertEqual(decoded.pages, ["Page one.", "Page two."])
        XCTAssertEqual(decoded.htmlBody, "<p>Hello</p>")
        XCTAssertTrue(decoded.isUnread)
        XCTAssertTrue(decoded.isStarred)
        XCTAssertEqual(decoded.messageCount, 3)
        XCTAssertEqual(decoded.timestamp, "2h")
        XCTAssertEqual(decoded.labelIds, ["INBOX", "STARRED"])
    }

    func test_missingIsStarred_defaultsFalse() throws {
        let json = """
        {
            "threadID": "t1",
            "senderName": "Bob",
            "senderInitials": "BO",
            "subject": "Sub",
            "pages": ["body"],
            "isUnread": false,
            "messageCount": 1,
            "timestamp": "1h"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CachedThread.self, from: json)
        XCTAssertFalse(decoded.isStarred)
    }

    func test_missingLabelIds_defaultsEmptyArray() throws {
        let json = """
        {
            "threadID": "t1",
            "senderName": "Bob",
            "senderInitials": "BO",
            "subject": "Sub",
            "pages": ["body"],
            "isUnread": false,
            "messageCount": 1,
            "timestamp": "1h"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CachedThread.self, from: json)
        XCTAssertEqual(decoded.labelIds, [])
    }

    func test_toModel_reconstructsCorrectEmailThread() {
        let thread = EmailThread(
            threadID: "xyz",
            sender: Sender(name: "Carol", email: "carol@test.com", initials: "CA"),
            subject: "Meeting Tomorrow",
            pages: ["See you there."],
            isUnread: false,
            isStarred: false,
            messageCount: 2,
            timestamp: "3d",
            labelIds: ["INBOX"]
        )

        let model = CachedThread(from: thread).toModel()

        XCTAssertEqual(model.threadID, "xyz")
        XCTAssertEqual(model.sender.name, "Carol")
        XCTAssertEqual(model.sender.email, "carol@test.com")
        XCTAssertEqual(model.subject, "Meeting Tomorrow")
        XCTAssertEqual(model.pages, ["See you there."])
        XCTAssertFalse(model.isUnread)
        XCTAssertFalse(model.isStarred)
        XCTAssertEqual(model.messageCount, 2)
        XCTAssertEqual(model.timestamp, "3d")
        XCTAssertEqual(model.labelIds, ["INBOX"])
    }
}
