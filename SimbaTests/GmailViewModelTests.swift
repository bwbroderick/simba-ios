import XCTest
@testable import Simba

@MainActor
final class GmailViewModelTests: XCTestCase {

    var viewModel: GmailViewModel!

    override func setUp() async throws {
        viewModel = GmailViewModel()
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    override func tearDown() async throws {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.requestHandler = nil
        viewModel = nil
    }

    // MARK: - fetchInbox

    func test_fetchInbox_withNoToken_setsErrorMessage() async {
        // No GIDSignIn user → refreshedAccessToken returns nil
        await viewModel.fetchInbox()
        XCTAssertEqual(viewModel.errorMessage, "Missing or expired access token.")
        XCTAssertTrue(viewModel.threads.isEmpty)
    }

    // MARK: - trashThread

    func test_trashThread_withNoAuth_setsErrorMessage() async {
        let thread = makeTestThread(id: "t1")
        viewModel.threads = [thread]
        await viewModel.trashThread(threadID: "t1")
        // Guard fails (no signed-in user), errorMessage set, threads unchanged
        XCTAssertEqual(viewModel.errorMessage, "Missing access token.")
        XCTAssertEqual(viewModel.threads.count, 1)
    }

    // MARK: - archiveThread

    func test_archiveThread_withNoAuth_setsErrorMessage() async {
        let thread = makeTestThread(id: "t1")
        viewModel.threads = [thread]
        await viewModel.archiveThread(threadID: "t1")
        XCTAssertEqual(viewModel.errorMessage, "Missing access token.")
        XCTAssertEqual(viewModel.threads.count, 1)
    }

    // MARK: - toggleStar

    func test_toggleStar_withNoAuth_threadsUnchanged() async {
        let thread = makeTestThread(id: "t1", isStarred: false)
        viewModel.threads = [thread]
        await viewModel.toggleStar(threadID: "t1", isCurrentlyStarred: false)
        // Guard fails silently (no errorMessage), threads unchanged
        XCTAssertEqual(viewModel.threads.first?.isStarred, false)
    }

    // MARK: - loadMoreThreads

    func test_loadMoreThreads_withNoNextPageToken_doesNotLoad() async {
        // nextPageToken is nil by default → early return
        XCTAssertFalse(viewModel.isLoadingMore)
        await viewModel.loadMoreThreads()
        XCTAssertFalse(viewModel.isLoadingMore)
    }

    func test_loadMoreThreads_whenAlreadyLoadingMore_doesNotLoad() async {
        viewModel.isLoadingMore = true
        await viewModel.loadMoreThreads()
        // Should return early because isLoadingMore is already true
        XCTAssertTrue(viewModel.isLoadingMore)
    }

    // MARK: - Helpers

    private func makeTestThread(id: String, isStarred: Bool = false) -> EmailThread {
        EmailThread(
            threadID: id,
            sender: Sender(name: "Test Sender", email: "test@test.com", initials: "TS"),
            subject: "Test Subject",
            pages: ["Test body"],
            isStarred: isStarred
        )
    }
}
