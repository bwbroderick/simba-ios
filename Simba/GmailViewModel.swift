import Foundation
import GoogleSignIn
import OSLog
import UIKit

struct GmailLabel: Identifiable {
    let id: String
    let name: String
    let type: String // "system" or "user"

    var displayName: String {
        switch id {
        case "INBOX": return "Inbox"
        case "SENT": return "Sent"
        case "DRAFT": return "Drafts"
        case "TRASH": return "Trash"
        case "SPAM": return "Spam"
        case "STARRED": return "Starred"
        case "IMPORTANT": return "Important"
        case "UNREAD": return "Unread"
        default: return name
        }
    }

    var iconName: String {
        switch id {
        case "INBOX": return "tray"
        case "SENT": return "paperplane"
        case "DRAFT": return "doc.text"
        case "TRASH": return "trash"
        case "SPAM": return "exclamationmark.shield"
        case "STARRED": return "star"
        case "IMPORTANT": return "bookmark"
        default: return "tag"
        }
    }

    static let defaultLabels: [GmailLabel] = [
        GmailLabel(id: "INBOX", name: "Inbox", type: "system"),
        GmailLabel(id: "STARRED", name: "Starred", type: "system"),
        GmailLabel(id: "SENT", name: "Sent", type: "system"),
        GmailLabel(id: "DRAFT", name: "Drafts", type: "system"),
        GmailLabel(id: "SPAM", name: "Spam", type: "system"),
        GmailLabel(id: "TRASH", name: "Trash", type: "system"),
    ]
}

struct GmailDraft: Identifiable {
    let id: String
    let messageId: String?
    let thread: EmailThread?
}

@MainActor
final class GmailViewModel: ObservableObject {
    @Published var threads: [EmailThread] = []
    @Published var searchResults: [EmailThread] = []
    @Published var isSignedIn = false
    @Published var isLoading = false
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var isSending = false

    // Labels
    @Published var labels: [GmailLabel] = GmailLabel.defaultLabels
    @Published var currentLabel: GmailLabel = GmailLabel.defaultLabels[0]
    @Published var userLabels: [GmailLabel] = []

    // Pagination
    @Published var isLoadingMore = false
    @Published var hasMorePages = false

    // Drafts
    @Published var drafts: [GmailDraft] = []

    private let clientID = "350262483118-bcrf17c6jrkfrum041she8njri3ju6m1.apps.googleusercontent.com"
    private let readOnlyScope = "https://www.googleapis.com/auth/gmail.readonly"
    private let sendScope = "https://www.googleapis.com/auth/gmail.send"
    private let modifyScope = "https://www.googleapis.com/auth/gmail.modify"
    private let cacheURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("gmail-cache.json")

    private var nextPageToken: String?
    private var searchNextPageToken: String?

    init() {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        loadCachedThreads()
    }

    func restoreSession() {
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            guard let self else { return }
            if let error {
                Logger.auth.error("Restore session failed: \(error.localizedDescription, privacy: .public)")
                self.errorMessage = error.localizedDescription
                self.isSignedIn = false
                return
            }

            self.isSignedIn = (user != nil)
            Logger.auth.info("Session restored: isSignedIn=\(self.isSignedIn, privacy: .public)")
            if self.isSignedIn {
                Task {
                    await self.fetchLabels()
                    await self.fetchInbox()
                }
            }
        }
    }

    func signIn() {
        guard let rootViewController = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?.rootViewController else {
            errorMessage = "Unable to find a window to present sign-in."
            return
        }

        GIDSignIn.sharedInstance.signIn(
            withPresenting: rootViewController,
            hint: nil,
            additionalScopes: [readOnlyScope, sendScope, modifyScope]
        ) { [weak self] result, error in
            guard let self else { return }
            if let error {
                Logger.auth.error("Sign-in failed: \(error.localizedDescription, privacy: .public)")
                self.errorMessage = error.localizedDescription
                self.isSignedIn = false
                return
            }

            self.isSignedIn = (result?.user != nil)
            Logger.auth.info("Sign-in result: isSignedIn=\(self.isSignedIn, privacy: .public)")
            Task {
                await self.fetchLabels()
                await self.fetchInbox()
            }
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        isSignedIn = false
        threads = []
        drafts = []
        currentLabel = GmailLabel.defaultLabels[0]
        Logger.auth.info("User signed out")
    }

    // MARK: - Labels

    func fetchLabels() async {
        guard let token = await refreshedAccessToken() else { return }

        do {
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/labels")!
            var request = URLRequest(url: url)
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                return
            }

            let labelsResponse = try JSONDecoder().decode(GmailLabelsResponse.self, from: data)
            let fetchedLabels = labelsResponse.labels ?? []

            userLabels = fetchedLabels
                .filter { $0.type == "user" }
                .map { GmailLabel(id: $0.id, name: $0.name, type: "user") }
                .sorted { $0.name.lowercased() < $1.name.lowercased() }

            labels = GmailLabel.defaultLabels + userLabels
        } catch {
            // Non-critical, keep defaults
        }
    }

    func fetchInboxUnreadCount() async -> Int? {
        guard let token = await refreshedAccessToken() else { return nil }
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/labels/INBOX")!
        var req = URLRequest(url: url)
        req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) == true
        else { return nil }
        return (try? JSONDecoder().decode(GmailInboxLabelDetail.self, from: data))?.threadsUnread
    }

    func switchLabel(_ label: GmailLabel) async {
        currentLabel = label
        threads = []
        nextPageToken = nil
        hasMorePages = false
        await fetchInbox()
    }

    // MARK: - Incremental Sync

    func performDeltaSync(token: String) async -> Bool {
        guard let historyId = lastHistoryId else {
            Logger.sync.info("Delta sync skipped: no lastHistoryId")
            return false
        }

        Logger.sync.info("Delta sync starting with historyId \(historyId, privacy: .public)")

        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/history")!
        components.queryItems = [
            URLQueryItem(name: "startHistoryId", value: historyId),
            URLQueryItem(name: "labelId", value: "INBOX"),
            URLQueryItem(name: "historyTypes", value: "messageAdded"),
            URLQueryItem(name: "historyTypes", value: "messageDeleted"),
            URLQueryItem(name: "historyTypes", value: "labelAdded"),
            URLQueryItem(name: "historyTypes", value: "labelRemoved"),
        ]
        var request = URLRequest(url: components.url!)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return false
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
            Logger.sync.warning("Delta sync 404: clearing lastHistoryId")
            lastHistoryId = nil
            return false
        }

        guard let historyResponse = try? JSONDecoder().decode(GmailHistoryResponse.self, from: data) else {
            return false
        }

        if let newHistoryId = historyResponse.historyId {
            lastHistoryId = newHistoryId
        }

        let records = historyResponse.history ?? []
        if records.isEmpty {
            Logger.sync.info("Delta sync: no changes")
            return true
        }

        var affectedThreadIds: Set<String> = []
        for record in records {
            for item in record.messagesAdded ?? [] {
                if let tid = item.message.threadId { affectedThreadIds.insert(tid) }
            }
            for item in record.messagesDeleted ?? [] {
                if let tid = item.message.threadId { affectedThreadIds.insert(tid) }
            }
            for item in record.labelsAdded ?? [] {
                if let tid = item.message.threadId { affectedThreadIds.insert(tid) }
            }
            for item in record.labelsRemoved ?? [] {
                if let tid = item.message.threadId { affectedThreadIds.insert(tid) }
            }
        }

        Logger.sync.info("Delta sync: \(affectedThreadIds.count, privacy: .public) affected threads")

        let refreshed = await loadThreadDetails(threadIDs: Array(affectedThreadIds), token: token)
        let refreshedIDs = Set(refreshed.compactMap { $0.threadID })
        let removedIDs = affectedThreadIds.subtracting(refreshedIDs)

        var updated = threads.filter { thread in
            guard let tid = thread.threadID else { return true }
            return !removedIDs.contains(tid) && !refreshedIDs.contains(tid)
        }
        updated = refreshed + updated
        threads = updated

        saveCachedThreads(threads)

        Logger.sync.info("Delta sync applied: \(refreshed.count, privacy: .public) updated, \(removedIDs.count, privacy: .public) removed")
        return true
    }

    // MARK: - Fetch Inbox

    func fetchInbox(unreadOnly: Bool = false, isRefresh: Bool = false) async {
        // Generate a unique ID for this fetch to detect stale results
        let fetchID = UUID()
        currentFetchID = fetchID

        guard let token = await refreshedAccessToken() else {
            errorMessage = "Missing or expired access token."
            return
        }

        // Attempt delta sync for INBOX pull-to-refresh before doing a full fetch
        if isRefresh && currentLabel.id == "INBOX" {
            Logger.network.info("fetchInbox: attempting delta sync")
            let didSync = await performDeltaSync(token: token)
            if didSync {
                Logger.network.info("fetchInbox: delta sync succeeded, skipping full fetch")
                isLoading = false
                return
            }
        }

        let labelIdForLog = currentLabel.id
        Logger.network.info("fetchInbox: full fetch for label \(labelIdForLog, privacy: .public)")

        // Only show loading indicator for initial loads, not pull-to-refresh
        // (pull-to-refresh has its own spinner; showing ProgressView changes
        // ScrollView content which causes SwiftUI to cancel the refresh task)
        if !isRefresh {
            isLoading = true
        }
        errorMessage = nil
        unreadOnlyActive = unreadOnly
        nextPageToken = nil

        do {
            let (threadIDs, pageToken, historyId) = try await fetchThreadIDs(
                token: token,
                labelId: currentLabel.id,
                unreadOnly: unreadOnly,
                pageToken: nil
            )

            nextPageToken = pageToken
            hasMorePages = pageToken != nil

            let loadedThreads = await loadThreadDetails(threadIDs: threadIDs, token: token)

            guard fetchID == currentFetchID else { return }

            threads = loadedThreads
            if !unreadOnly && currentLabel.id == "INBOX" {
                if let historyId {
                    lastHistoryId = historyId
                }
                saveCachedThreads(loadedThreads)
            }

            Logger.network.info("fetchInbox: loaded \(loadedThreads.count, privacy: .public) threads")
            ContactStore.shared.extract(from: loadedThreads)
            HTMLSnapshotCache.shared.preRenderInBackground(threads: loadedThreads)
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession throws URLError(.cancelled) when the Swift task is cancelled;
            // this is different from CancellationError and must be caught separately
            return
        } catch {
            if fetchID == currentFetchID {
                errorMessage = error.localizedDescription
            }
        }

        if fetchID == currentFetchID {
            isLoading = false
        }
    }

    func loadMoreThreads() async {
        guard let pageToken = nextPageToken, !isLoadingMore else { return }

        guard let token = await refreshedAccessToken() else { return }

        isLoadingMore = true

        do {
            let (threadIDs, newPageToken, _) = try await fetchThreadIDs(
                token: token,
                labelId: currentLabel.id,
                unreadOnly: unreadOnlyActive,
                pageToken: pageToken
            )

            nextPageToken = newPageToken
            hasMorePages = newPageToken != nil

            let newThreads = await loadThreadDetails(threadIDs: threadIDs, token: token)

            // Deduplicate
            let existingIDs = Set(threads.compactMap { $0.threadID })
            let unique = newThreads.filter { thread in
                guard let tid = thread.threadID else { return true }
                return !existingIDs.contains(tid)
            }

            threads.append(contentsOf: unique)
        } catch {
            // Silent failure for pagination
        }

        isLoadingMore = false
    }

    private func fetchThreadIDs(
        token: String,
        labelId: String,
        unreadOnly: Bool,
        pageToken: String?
    ) async throws -> ([String], String?, String?) {
        var listComponents = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/threads")!
        var queryItems = [
            URLQueryItem(name: "maxResults", value: "20"),
        ]

        // STARRED and DRAFT don't use labelIds the same way
        if labelId == "STARRED" {
            queryItems.append(URLQueryItem(name: "q", value: "is:starred"))
        } else if labelId == "DRAFT" {
            // Drafts are fetched separately
        } else {
            queryItems.append(URLQueryItem(name: "labelIds", value: labelId))
        }

        if unreadOnly {
            queryItems.append(URLQueryItem(name: "q", value: "is:unread"))
        }
        if let pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }

        listComponents.queryItems = queryItems
        let listURL = listComponents.url!
        var listRequest = URLRequest(url: listURL)
        listRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (listData, listURLResponse) = try await URLSession.shared.data(for: listRequest)
        if let httpResponse = listURLResponse as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw NSError(domain: "GmailAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch threads (HTTP \(httpResponse.statusCode))"])
        }
        let listResponse = try JSONDecoder().decode(GmailThreadListResponse.self, from: listData)

        let threadIDs = (listResponse.threads ?? []).map { $0.id }
        return (threadIDs, listResponse.nextPageToken, listResponse.historyId)
    }

    private func loadThreadDetails(threadIDs: [String], token: String) async -> [EmailThread] {
        var loadedThreads: [EmailThread] = []

        await withTaskGroup(of: (Int, EmailThread?).self) { group in
            for (index, threadID) in threadIDs.enumerated() {
                group.addTask {
                    let thread = await self.fetchSingleThread(threadID: threadID, token: token)
                    return (index, thread)
                }
            }

            var results: [(Int, EmailThread)] = []
            for await (index, thread) in group {
                if let thread {
                    results.append((index, thread))
                }
            }

            loadedThreads = results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }

        return loadedThreads
    }

    private func fetchSingleThread(threadID: String, token: String) async -> EmailThread? {
        do {
            let detailURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/threads/\(threadID)?format=full")!
            var detailRequest = URLRequest(url: detailURL)
            detailRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (detailData, detailURLResponse) = try await URLSession.shared.data(for: detailRequest)
            if let httpResponse = detailURLResponse as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                return nil
            }
            let threadDetail = try JSONDecoder().decode(GmailInboxThreadDetail.self, from: detailData)
            return Self.makeThread(from: threadDetail)
        } catch {
            return nil
        }
    }

    // MARK: - Mark Read

    func queueMarkRead(threadID: String) {
        pendingReadThreadIDs.insert(threadID)
        readTask?.cancel()
        readTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await self?.flushMarkRead()
        }
    }

    private func flushMarkRead() async {
        guard !pendingReadThreadIDs.isEmpty else { return }
        let threadIDs = pendingReadThreadIDs
        pendingReadThreadIDs.removeAll()

        for threadID in threadIDs {
            await markThreadRead(threadID: threadID)
        }
    }

    private func markThreadRead(threadID: String) async {
        guard let token = GIDSignIn.sharedInstance.currentUser?.accessToken.tokenString else {
            return
        }

        do {
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/threads/\(threadID)/modify")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["removeLabelIds": ["UNREAD"]], options: [])

            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                return
            }
        } catch {
            return
        }

        if unreadOnlyActive {
            threads.removeAll { $0.threadID == threadID }
        } else {
            threads = threads.map { thread in
                if thread.threadID == threadID {
                    return EmailThread(
                        threadID: thread.threadID,
                        sender: thread.sender,
                        subject: thread.subject,
                        pages: thread.pages,
                        htmlBody: thread.htmlBody,
                        isUnread: false,
                        isStarred: thread.isStarred,
                        messageCount: thread.messageCount,
                        timestamp: thread.timestamp,
                        messages: thread.messages,
                        labelIds: thread.labelIds,
                        attachments: thread.attachments,
                        debugVisibility: thread.debugVisibility
                    )
                }
                return thread
            }
            if currentLabel.id == "INBOX" {
                saveCachedThreads(threads)
            }
        }
    }

    // MARK: - Trash

    func trashThread(threadID: String) async {
        guard let token = GIDSignIn.sharedInstance.currentUser?.accessToken.tokenString else {
            errorMessage = "Missing access token."
            return
        }

        Logger.network.info("Trashing thread \(threadID, privacy: .private)")
        do {
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/threads/\(threadID)/trash")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            _ = try await URLSession.shared.data(for: request)

            threads.removeAll { $0.threadID == threadID }
            if currentLabel.id == "INBOX" {
                saveCachedThreads(threads)
            }
        } catch {
            errorMessage = "Failed to delete: \(error.localizedDescription)"
        }
    }

    // MARK: - Archive

    func archiveThread(threadID: String) async {
        guard let token = GIDSignIn.sharedInstance.currentUser?.accessToken.tokenString else {
            errorMessage = "Missing access token."
            return
        }

        Logger.network.info("Archiving thread \(threadID, privacy: .private)")
        do {
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/threads/\(threadID)/modify")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["removeLabelIds": ["INBOX"]], options: [])

            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                errorMessage = "Failed to archive: HTTP \(httpResponse.statusCode)"
                return
            }

            threads.removeAll { $0.threadID == threadID }
            if currentLabel.id == "INBOX" {
                saveCachedThreads(threads)
            }
        } catch {
            errorMessage = "Failed to archive: \(error.localizedDescription)"
        }
    }

    // MARK: - Star/Unstar

    func toggleStar(threadID: String, isCurrentlyStarred: Bool) async {
        guard let token = GIDSignIn.sharedInstance.currentUser?.accessToken.tokenString else {
            return
        }

        Logger.network.info("Toggling star for thread \(threadID, privacy: .private), currently starred: \(isCurrentlyStarred, privacy: .public)")
        let body: [String: [String]] = isCurrentlyStarred
            ? ["removeLabelIds": ["STARRED"]]
            : ["addLabelIds": ["STARRED"]]

        do {
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/threads/\(threadID)/modify")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                return
            }

            threads = threads.map { thread in
                if thread.threadID == threadID {
                    return EmailThread(
                        threadID: thread.threadID,
                        sender: thread.sender,
                        subject: thread.subject,
                        pages: thread.pages,
                        htmlBody: thread.htmlBody,
                        isUnread: thread.isUnread,
                        isStarred: !isCurrentlyStarred,
                        messageCount: thread.messageCount,
                        timestamp: thread.timestamp,
                        messages: thread.messages,
                        labelIds: thread.labelIds,
                        attachments: thread.attachments,
                        debugVisibility: thread.debugVisibility
                    )
                }
                return thread
            }
        } catch {
            // Silent failure
        }
    }

    // MARK: - Send Email

    func sendEmail(to: String, subject: String, body: String, cc: String = "", bcc: String = "") async {
        guard let token = GIDSignIn.sharedInstance.currentUser?.accessToken.tokenString else {
            errorMessage = "Missing access token."
            return
        }

        isSending = true
        errorMessage = nil

        let rawMessage = Self.buildRawMessage(to: to, subject: subject, body: body, cc: cc, bcc: bcc)

        guard let data = rawMessage.data(using: .utf8) else {
            errorMessage = "Failed to encode message."
            isSending = false
            return
        }

        var encoded = data.base64EncodedString()
        encoded = encoded.replacingOccurrences(of: "+", with: "-")
        encoded = encoded.replacingOccurrences(of: "/", with: "_")
        encoded = encoded.replacingOccurrences(of: "=", with: "")

        do {
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/send")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["raw": encoded], options: [])

            _ = try await URLSession.shared.data(for: request)
        } catch {
            errorMessage = error.localizedDescription
        }

        isSending = false
    }

    // MARK: - Attachments

    func downloadAttachment(messageId: String, attachmentId: String) async -> Data? {
        guard let token = await refreshedAccessToken() else { return nil }

        do {
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(messageId)/attachments/\(attachmentId)")!
            var request = URLRequest(url: url)
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                return nil
            }

            let attachmentResponse = try JSONDecoder().decode(GmailAttachmentResponse.self, from: data)
            guard let base64Data = attachmentResponse.data else { return nil }

            return Self.decodeBase64URLData(base64Data)
        } catch {
            return nil
        }
    }

    // MARK: - Drafts

    func fetchDrafts() async {
        guard let token = await refreshedAccessToken() else { return }

        do {
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/drafts?maxResults=20")!
            var request = URLRequest(url: url)
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                return
            }

            let draftsResponse = try JSONDecoder().decode(GmailDraftsListResponse.self, from: data)
            let draftRefs = draftsResponse.drafts ?? []

            var loadedDrafts: [GmailDraft] = []
            for draftRef in draftRefs {
                let draft = await fetchDraftDetail(draftId: draftRef.id, token: token)
                if let draft {
                    loadedDrafts.append(draft)
                }
            }

            drafts = loadedDrafts
        } catch {
            // Silent failure
        }
    }

    private func fetchDraftDetail(draftId: String, token: String) async -> GmailDraft? {
        do {
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/drafts/\(draftId)")!
            var request = URLRequest(url: url)
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                return nil
            }

            let draftDetail = try JSONDecoder().decode(GmailDraftDetail.self, from: data)
            let message = draftDetail.message

            let headers = message.payload?.headers ?? []
            let subject = headers.first(where: { $0.name.lowercased() == "subject" })?.value ?? "(No subject)"
            let toValue = headers.first(where: { $0.name.lowercased() == "to" })?.value ?? ""
            let body = Self.extractBodies(from: message.payload)
            let snippet = message.snippet ?? ""

            let thread = EmailThread(
                threadID: message.threadId,
                sender: Sender(name: toValue, email: toValue, initials: "DR"),
                subject: subject,
                pages: [snippet],
                htmlBody: body.html,
                messageCount: 0,
                timestamp: "",
                labelIds: ["DRAFT"]
            )

            return GmailDraft(id: draftId, messageId: message.id, thread: thread)
        } catch {
            return nil
        }
    }

    func createDraft(to: String, subject: String, body: String, cc: String = "", bcc: String = "") async -> String? {
        guard let token = await refreshedAccessToken() else { return nil }

        let rawMessage = Self.buildRawMessage(to: to, subject: subject, body: body, cc: cc, bcc: bcc)
        guard let data = rawMessage.data(using: .utf8) else { return nil }

        var encoded = data.base64EncodedString()
        encoded = encoded.replacingOccurrences(of: "+", with: "-")
        encoded = encoded.replacingOccurrences(of: "/", with: "_")
        encoded = encoded.replacingOccurrences(of: "=", with: "")

        do {
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/drafts")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "message": ["raw": encoded]
            ], options: [])

            let (responseData, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(GmailDraftCreateResponse.self, from: responseData)
            return response.id
        } catch {
            return nil
        }
    }

    func updateDraft(draftId: String, to: String, subject: String, body: String, cc: String = "", bcc: String = "") async {
        guard let token = await refreshedAccessToken() else { return }

        let rawMessage = Self.buildRawMessage(to: to, subject: subject, body: body, cc: cc, bcc: bcc)
        guard let data = rawMessage.data(using: .utf8) else { return }

        var encoded = data.base64EncodedString()
        encoded = encoded.replacingOccurrences(of: "+", with: "-")
        encoded = encoded.replacingOccurrences(of: "/", with: "_")
        encoded = encoded.replacingOccurrences(of: "=", with: "")

        do {
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/drafts/\(draftId)")!
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "message": ["raw": encoded]
            ], options: [])

            _ = try await URLSession.shared.data(for: request)
        } catch {
            // Silent failure
        }
    }

    func deleteDraft(draftId: String) async {
        guard let token = await refreshedAccessToken() else { return }

        do {
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/drafts/\(draftId)")!
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            _ = try await URLSession.shared.data(for: request)
            drafts.removeAll { $0.id == draftId }
        } catch {
            // Silent failure
        }
    }

    // MARK: - Search

    func search(query: String) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }

        guard let token = await refreshedAccessToken() else {
            errorMessage = "Missing or expired access token."
            return
        }

        isSearching = true
        errorMessage = nil

        do {
            var listComponents = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/threads")!
            listComponents.queryItems = [
                URLQueryItem(name: "maxResults", value: "20"),
                URLQueryItem(name: "q", value: query)
            ]

            let listURL = listComponents.url!
            var listRequest = URLRequest(url: listURL)
            listRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (listData, listURLResponse) = try await URLSession.shared.data(for: listRequest)
            if let httpResponse = listURLResponse as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                throw NSError(domain: "GmailAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Search failed (HTTP \(httpResponse.statusCode))"])
            }
            let listResponse = try JSONDecoder().decode(GmailThreadListResponse.self, from: listData)

            let threadIDs = (listResponse.threads ?? []).map { $0.id }
            let loadedThreads = await loadThreadDetails(threadIDs: threadIDs, token: token)

            searchResults = loadedThreads
        } catch is CancellationError {
            // Task was cancelled - not an error to display
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession cancelled - not an error to display
        } catch {
            errorMessage = error.localizedDescription
        }

        isSearching = false
    }

    func clearSearchResults() {
        searchResults = []
    }

    // MARK: - Thread Parsing

    static func makeThread(from threadDetail: GmailInboxThreadDetail) -> EmailThread? {
        guard let firstMessage = threadDetail.messages.first else { return nil }

        let headers = firstMessage.payload?.headers ?? []
        let subject = headers.first(where: { $0.name.lowercased() == "subject" })?.value ?? "(No subject)"
        let fromValue = headers.first(where: { $0.name.lowercased() == "from" })?.value ?? "Unknown Sender"
        let dateValue = headers.first(where: { $0.name.lowercased() == "date" })?.value ?? ""

        let senderName = parseSenderName(from: fromValue)
        let senderEmail = parseEmail(from: fromValue)
        let initials = initialsFromName(senderName)

        let sender = Sender(name: senderName, email: senderEmail, initials: initials)
        let snippet = firstMessage.snippet ?? ""
        let pages = TextChunker.chunk(snippet)
        let body = extractBodies(from: firstMessage.payload)

        let isUnread = firstMessage.labelIds?.contains("UNREAD") ?? false
        let isStarred = threadDetail.messages.contains { $0.labelIds?.contains("STARRED") ?? false }
        let messageCount = threadDetail.messages.count

        // Collect all label IDs across all messages
        var allLabelIds: Set<String> = []
        for msg in threadDetail.messages {
            if let ids = msg.labelIds {
                allLabelIds.formUnion(ids)
            }
        }

        // Extract attachments from the first message
        let attachments = extractAttachments(from: firstMessage.payload, messageId: firstMessage.id ?? threadDetail.id)

        return EmailThread(
            threadID: threadDetail.id,
            sender: sender,
            subject: subject,
            pages: pages.isEmpty ? [snippet] : pages,
            htmlBody: body.html,
            isUnread: isUnread,
            isStarred: isStarred,
            messageCount: messageCount,
            timestamp: relativeTimestamp(from: dateValue),
            messages: [],
            labelIds: Array(allLabelIds),
            attachments: attachments,
            debugVisibility: nil
        )
    }

    // MARK: - Attachment Extraction

    static func extractAttachments(from payload: GmailMessagePayload?, messageId: String) -> [EmailAttachment] {
        GmailMessageParser.extractAttachments(from: payload, messageId: messageId)
    }

    // MARK: - Helpers

    static func parseSenderName(from value: String) -> String {
        if let namePart = value.split(separator: "<").first {
            let trimmed = namePart.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !trimmed.isEmpty {
                if trimmed.contains("@"), !trimmed.contains(" ") {
                    return displayNameFromEmail(trimmed)
                }
                return trimmed
            }
        }

        if let emailPart = value.split(separator: "<").last?.replacingOccurrences(of: ">", with: "") {
            let email = emailPart.trimmingCharacters(in: .whitespacesAndNewlines)
            return displayNameFromEmail(email)
        }

        return value
    }

    static func parseEmail(from value: String) -> String? {
        if let emailPart = value.split(separator: "<").last?.replacingOccurrences(of: ">", with: "") {
            return emailPart.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if value.contains("@") {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func displayNameFromEmail(_ email: String) -> String {
        guard let local = email.split(separator: "@").first else { return email }
        return local
            .split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" })
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    static func initialsFromName(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? "?"
        let second = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + second).uppercased()
    }

    nonisolated static func relativeTimestamp(from headerValue: String) -> String {
        guard let date = parseDate(from: headerValue) else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Now" }
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        return "\(days)d"
    }

    nonisolated static func parseDate(from headerValue: String) -> Date? {
        let cleaned = headerValue.components(separatedBy: " (").first ?? headerValue
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm Z",
            "dd MMM yyyy HH:mm Z"
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) {
                return date
            }
        }

        let isoFormatter = ISO8601DateFormatter()
        return isoFormatter.date(from: cleaned)
    }

    static func extractBodies(from payload: GmailMessagePayload?) -> (html: String?, text: String?) {
        guard let payload else { return (nil, nil) }
        let parts = payload.parts ?? []
        var htmlBody: String?
        var textBody: String?

        func walk(_ part: GmailMessagePart) {
            if let mime = part.mimeType?.lowercased() {
                if mime == "text/html", htmlBody == nil {
                    htmlBody = decodeBase64URL(part.body?.data)
                } else if mime == "text/plain", textBody == nil {
                    textBody = decodeBase64URL(part.body?.data)
                }
            }

            part.parts?.forEach { walk($0) }
        }

        if parts.isEmpty {
            if let mime = payload.mimeType?.lowercased() {
                if mime == "text/html" {
                    htmlBody = decodeBase64URL(payload.body?.data)
                } else if mime == "text/plain" {
                    textBody = decodeBase64URL(payload.body?.data)
                }
            }
        } else {
            parts.forEach { walk($0) }
        }

        return (htmlBody, textBody)
    }

    static func decodeBase64URL(_ value: String?) -> String? {
        guard var value else { return nil }
        value = value.replacingOccurrences(of: "-", with: "+")
        value = value.replacingOccurrences(of: "_", with: "/")
        let paddedLength = ((value.count + 3) / 4) * 4
        value = value.padding(toLength: paddedLength, withPad: "=", startingAt: 0)
        guard let data = Data(base64Encoded: value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    nonisolated static func buildRawMessage(to: String, subject: String, body: String, cc: String = "", bcc: String = "") -> String {
        var headers = [
            "To: \(to)",
            "Subject: \(subject)",
            "Content-Type: text/plain; charset=\"UTF-8\""
        ]
        if !cc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            headers.insert("Cc: \(cc)", at: 1)
        }
        if !bcc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            headers.insert("Bcc: \(bcc)", at: cc.isEmpty ? 1 : 2)
        }
        return (headers + ["", body]).joined(separator: "\r\n")
    }

    static func decodeBase64URLData(_ value: String) -> Data? {
        var v = value.replacingOccurrences(of: "-", with: "+")
        v = v.replacingOccurrences(of: "_", with: "/")
        let paddedLength = ((v.count + 3) / 4) * 4
        v = v.padding(toLength: paddedLength, withPad: "=", startingAt: 0)
        return Data(base64Encoded: v)
    }

    // MARK: - Cache

    private func loadCachedThreads() {
        Logger.cache.info("Loading cached threads")
        guard let data = try? Data(contentsOf: cacheURL) else { return }
        guard let cached = try? JSONDecoder().decode([CachedThread].self, from: data) else { return }
        threads = cached.map { $0.toModel() }
        Logger.cache.debug("Loaded \(cached.count, privacy: .public) threads from cache")
    }

    private func saveCachedThreads(_ threads: [EmailThread]) {
        Logger.cache.debug("Saving \(threads.count, privacy: .public) threads to cache")
        let cached = threads.map { CachedThread(from: $0) }
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? data.write(to: cacheURL, options: [.atomic])
    }

    func refreshedAccessToken() async -> String? {
        guard let user = GIDSignIn.sharedInstance.currentUser else { return nil }
        return await withCheckedContinuation { continuation in
            user.refreshTokensIfNeeded { user, error in
                if let error {
                    Logger.auth.error("Token refresh failed: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: user?.accessToken.tokenString)
            }
        }
    }

    private var pendingReadThreadIDs: Set<String> = []
    private var readTask: Task<Void, Never>?
    private var unreadOnlyActive = false
    private var currentFetchID: UUID?

    private var lastHistoryId: String? {
        get { UserDefaults.standard.string(forKey: "simba.lastHistoryId") }
        set { UserDefaults.standard.set(newValue, forKey: "simba.lastHistoryId") }
    }
}

// MARK: - API Response Models

struct GmailMessageListResponse: Decodable {
    let messages: [GmailMessageRef]?
}

struct GmailMessageRef: Decodable {
    let id: String
}

struct GmailThreadListResponse: Decodable {
    let threads: [GmailThreadRef]?
    let nextPageToken: String?
    let historyId: String?
}

struct GmailThreadRef: Decodable {
    let id: String
}

struct GmailInboxThreadDetail: Decodable {
    let id: String
    let messages: [GmailMessageDetail]
}

struct GmailMessageDetail: Decodable {
    let id: String?
    let snippet: String?
    let payload: GmailMessagePayload?
    let threadId: String?
    let labelIds: [String]?
}

struct GmailMessagePayload: Decodable {
    let headers: [GmailMessageHeader]
    let mimeType: String?
    let body: GmailMessageBody?
    let parts: [GmailMessagePart]?
}

struct GmailMessageHeader: Decodable {
    let name: String
    let value: String
}

struct GmailMessagePart: Decodable {
    let mimeType: String?
    let filename: String?
    let body: GmailMessageBody?
    let parts: [GmailMessagePart]?
}

struct GmailMessageBody: Decodable {
    let data: String?
    let size: Int?
    let attachmentId: String?
}

struct GmailAttachmentResponse: Decodable {
    let data: String?
    let size: Int?
}

struct GmailLabelsResponse: Decodable {
    struct Label: Decodable {
        let id: String
        let name: String
        let type: String?
    }
    let labels: [Label]?
}

struct GmailDraftsListResponse: Decodable {
    struct DraftRef: Decodable {
        let id: String
    }
    let drafts: [DraftRef]?
}

struct GmailDraftDetail: Decodable {
    let id: String
    let message: GmailMessageDetail
}

struct GmailDraftCreateResponse: Decodable {
    let id: String
}

// MARK: - History API Models

struct GmailHistoryResponse: Decodable {
    let history: [GmailHistoryRecord]?
    let historyId: String?
    let nextPageToken: String?
}

struct GmailHistoryRecord: Decodable {
    let id: String
    let messagesAdded: [GmailHistoryMessage]?
    let messagesDeleted: [GmailHistoryMessage]?
    let labelsAdded: [GmailHistoryLabelChange]?
    let labelsRemoved: [GmailHistoryLabelChange]?
}

struct GmailHistoryMessage: Decodable {
    let message: GmailHistoryMessageRef
}

struct GmailHistoryMessageRef: Decodable {
    let id: String
    let threadId: String?
    let labelIds: [String]?
}

struct GmailHistoryLabelChange: Decodable {
    let message: GmailHistoryMessageRef
    let labelIds: [String]?
}

struct GmailInboxLabelDetail: Decodable {
    let threadsUnread: Int?
    let messagesUnread: Int?
}

// MARK: - Cache Model

struct CachedThread: Codable {
    let threadID: String?
    let senderName: String
    let senderEmail: String?
    let senderInitials: String
    let subject: String
    let pages: [String]
    let htmlBody: String?
    let isUnread: Bool
    let isStarred: Bool
    let messageCount: Int
    let timestamp: String
    let labelIds: [String]

    enum CodingKeys: String, CodingKey {
        case threadID, senderName, senderEmail, senderInitials, subject, pages, htmlBody
        case isUnread, isStarred, messageCount, timestamp, labelIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadID = try container.decodeIfPresent(String.self, forKey: .threadID)
        senderName = try container.decode(String.self, forKey: .senderName)
        senderEmail = try container.decodeIfPresent(String.self, forKey: .senderEmail)
        senderInitials = try container.decode(String.self, forKey: .senderInitials)
        subject = try container.decode(String.self, forKey: .subject)
        pages = try container.decode([String].self, forKey: .pages)
        htmlBody = try container.decodeIfPresent(String.self, forKey: .htmlBody)
        isUnread = try container.decode(Bool.self, forKey: .isUnread)
        isStarred = try container.decodeIfPresent(Bool.self, forKey: .isStarred) ?? false
        messageCount = try container.decode(Int.self, forKey: .messageCount)
        timestamp = try container.decode(String.self, forKey: .timestamp)
        labelIds = try container.decodeIfPresent([String].self, forKey: .labelIds) ?? []
    }

    init(from thread: EmailThread) {
        threadID = thread.threadID
        senderName = thread.sender.name
        senderEmail = thread.sender.email
        senderInitials = thread.sender.initials
        subject = thread.subject
        pages = thread.pages
        htmlBody = thread.htmlBody
        isUnread = thread.isUnread
        isStarred = thread.isStarred
        messageCount = thread.messageCount
        timestamp = thread.timestamp
        labelIds = thread.labelIds
    }

    func toModel() -> EmailThread {
        EmailThread(
            threadID: threadID,
            sender: Sender(name: senderName, email: senderEmail, initials: senderInitials),
            subject: subject,
            pages: pages,
            htmlBody: htmlBody,
            isUnread: isUnread,
            isStarred: isStarred,
            messageCount: messageCount,
            timestamp: timestamp,
            labelIds: labelIds
        )
    }
}
