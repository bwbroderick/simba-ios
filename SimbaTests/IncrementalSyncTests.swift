import XCTest
@testable import Simba

@MainActor
final class IncrementalSyncTests: XCTestCase {

    var viewModel: GmailViewModel!

    override func setUp() async throws {
        viewModel = GmailViewModel()
        URLProtocol.registerClass(MockURLProtocol.self)
        UserDefaults.standard.removeObject(forKey: "simba.lastHistoryId")
    }

    override func tearDown() async throws {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.requestHandler = nil
        UserDefaults.standard.removeObject(forKey: "simba.lastHistoryId")
        viewModel = nil
    }

    // MARK: - No lastHistoryId

    func test_noLastHistoryId_returnsFalse_makesNoNetworkCall() async {
        var requestMade = false
        MockURLProtocol.requestHandler = { _ in
            requestMade = true
            throw URLError(.notConnectedToInternet)
        }

        let result = await viewModel.performDeltaSync(token: "fake-token")
        XCTAssertFalse(result)
        XCTAssertFalse(requestMade)
    }

    // MARK: - History API 404

    func test_historyApi404_returnsFalse_clearsHistoryId() async {
        UserDefaults.standard.set("12345", forKey: "simba.lastHistoryId")

        MockURLProtocol.requestHandler = { request in
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (resp, Data())
        }

        let result = await viewModel.performDeltaSync(token: "fake-token")
        XCTAssertFalse(result)
        XCTAssertNil(UserDefaults.standard.string(forKey: "simba.lastHistoryId"))
    }

    // MARK: - Empty history

    func test_emptyHistory_returnsTrue_updatesHistoryId() async {
        UserDefaults.standard.set("12345", forKey: "simba.lastHistoryId")

        let historyJSON = """
        {"historyId": "12999", "history": []}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (resp, historyJSON)
        }

        let initialCount = viewModel.threads.count
        let result = await viewModel.performDeltaSync(token: "fake-token")

        XCTAssertTrue(result)
        XCTAssertEqual(viewModel.threads.count, initialCount)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "simba.lastHistoryId"), "12999")
    }

    // MARK: - messagesAdded → thread inserted

    func test_messagesAdded_insertsThread() async {
        UserDefaults.standard.set("12345", forKey: "simba.lastHistoryId")

        let historyJSON = """
        {
            "historyId": "12999",
            "history": [{
                "id": "12346",
                "messagesAdded": [{
                    "message": {"id": "msg1", "threadId": "thread1", "labelIds": ["INBOX"]}
                }]
            }]
        }
        """.data(using: .utf8)!

        let threadJSON = """
        {
            "id": "thread1",
            "messages": [{
                "id": "msg1",
                "snippet": "New message snippet",
                "payload": {
                    "headers": [
                        {"name": "Subject", "value": "New Thread"},
                        {"name": "From", "value": "Sender <sender@test.com>"},
                        {"name": "Date", "value": "Mon, 01 Jan 2024 12:00:00 +0000"}
                    ]
                },
                "labelIds": ["INBOX"]
            }]
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            if request.url?.absoluteString.contains("/history") == true {
                return (resp, historyJSON)
            } else {
                return (resp, threadJSON)
            }
        }

        let result = await viewModel.performDeltaSync(token: "fake-token")
        XCTAssertTrue(result)
        XCTAssertTrue(viewModel.threads.contains { $0.threadID == "thread1" })
    }

    // MARK: - messagesDeleted → thread 404 → removed from threads

    func test_messagesDeleted_thread404_removesFromThreads() async {
        UserDefaults.standard.set("12345", forKey: "simba.lastHistoryId")

        let existing = EmailThread(
            threadID: "thread1",
            sender: Sender(name: "Test", email: "t@t.com", initials: "TT"),
            subject: "Old Thread",
            pages: ["body"]
        )
        viewModel.threads = [existing]

        let historyJSON = """
        {
            "historyId": "12999",
            "history": [{
                "id": "12346",
                "messagesDeleted": [{
                    "message": {"id": "msg1", "threadId": "thread1", "labelIds": ["INBOX"]}
                }]
            }]
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            if request.url?.absoluteString.contains("/history") == true {
                let resp = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (resp, historyJSON)
            } else {
                // Thread detail 404 — thread was deleted
                let resp = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 404,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (resp, Data())
            }
        }

        let result = await viewModel.performDeltaSync(token: "fake-token")
        XCTAssertTrue(result)
        XCTAssertFalse(viewModel.threads.contains { $0.threadID == "thread1" })
    }
}
