import Foundation
import GoogleSignIn
import UIKit

@MainActor
final class GmailViewModel: ObservableObject {
    @Published var threads: [EmailThread] = []
    @Published var searchResults: [EmailThread] = []
    @Published var isSignedIn = false
    @Published var isLoading = false
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var isSending = false

    private let clientID = "350262483118-bcrf17c6jrkfrum041she8njri3ju6m1.apps.googleusercontent.com"
    private let readOnlyScope = "https://www.googleapis.com/auth/gmail.readonly"
    private let sendScope = "https://www.googleapis.com/auth/gmail.send"
    private let modifyScope = "https://www.googleapis.com/auth/gmail.modify"
    private let cacheURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("gmail-cache.json")

    init() {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        loadCachedThreads()
    }

    func restoreSession() {
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            guard let self else { return }
            if let error {
                self.errorMessage = error.localizedDescription
                self.isSignedIn = false
                return
            }

            self.isSignedIn = (user != nil)
            if self.isSignedIn {
                Task { await self.fetchInbox() }
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
                self.errorMessage = error.localizedDescription
                self.isSignedIn = false
                return
            }

            self.isSignedIn = (result?.user != nil)
            Task { await self.fetchInbox() }
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        isSignedIn = false
        threads = []
    }

    func fetchInbox(unreadOnly: Bool = false, isRefresh: Bool = false) async {
        // Generate a unique ID for this fetch to detect stale results
        let fetchID = UUID()
        currentFetchID = fetchID

        // Refresh access token before making API calls
        guard let token = await refreshedAccessToken() else {
            errorMessage = "Missing or expired access token."
            return
        }

        // Only show loading indicator for initial loads, not pull-to-refresh
        // (pull-to-refresh has its own spinner; showing ProgressView changes
        // ScrollView content which causes SwiftUI to cancel the refresh task)
        if !isRefresh {
            isLoading = true
        }
        errorMessage = nil
        unreadOnlyActive = unreadOnly

        do {
            var listComponents = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/threads")!
            var queryItems = [
                URLQueryItem(name: "maxResults", value: "20"),
                URLQueryItem(name: "labelIds", value: "INBOX")
            ]
            if unreadOnly {
                queryItems.append(URLQueryItem(name: "q", value: "is:unread"))
            }
            listComponents.queryItems = queryItems
            let listURL = listComponents.url!
            var listRequest = URLRequest(url: listURL)
            listRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (listData, listURLResponse) = try await URLSession.shared.data(for: listRequest)
            if let httpResponse = listURLResponse as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                throw NSError(domain: "GmailAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch inbox (HTTP \(httpResponse.statusCode))"])
            }
            let listResponse = try JSONDecoder().decode(GmailThreadListResponse.self, from: listData)

            let threadIDs = (listResponse.threads ?? []).map { $0.id }
            var loadedThreads: [EmailThread] = []

            for threadID in threadIDs {
                let detailURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/threads/\(threadID)?format=full")!
                var detailRequest = URLRequest(url: detailURL)
                detailRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                let (detailData, detailURLResponse) = try await URLSession.shared.data(for: detailRequest)
                if let httpResponse = detailURLResponse as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                    continue // Skip threads that fail to load
                }
                let threadDetail = try JSONDecoder().decode(GmailInboxThreadDetail.self, from: detailData)

                if let thread = Self.makeThread(from: threadDetail) {
                    loadedThreads.append(thread)
                }
            }

            // Only update if this is still the most recent fetch (prevents race conditions)
            guard fetchID == currentFetchID else { return }

            threads = loadedThreads
            // Only save to cache when showing all emails, not filtered unread-only view
            if !unreadOnly {
                saveCachedThreads(loadedThreads)
            }

            ContactStore.shared.extract(from: loadedThreads)
            HTMLSnapshotCache.shared.preRenderInBackground(threads: loadedThreads)
        } catch is CancellationError {
            // Task was cancelled (e.g., view dismissed) - not an error to display
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession throws URLError(.cancelled) when the Swift task is cancelled;
            // this is different from CancellationError and must be caught separately
            return
        } catch {
            // Only show error if this is still the most recent fetch
            if fetchID == currentFetchID {
                errorMessage = error.localizedDescription
            }
        }

        // Only update loading state if this is still the most recent fetch
        if fetchID == currentFetchID {
            isLoading = false
        }
    }

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
                errorMessage = "Failed to delete: HTTP \(httpResponse.statusCode)"
                return
            }
        } catch {
            return
        }

        if unreadOnlyActive {
            // Remove from display list but don't save to cache - this is a filtered view
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
                        messageCount: thread.messageCount,
                        timestamp: thread.timestamp,
                        messages: thread.messages,
                        debugVisibility: thread.debugVisibility
                    )
                }
                return thread
            }
            // Only save to cache when in "all emails" view to preserve full inbox state
            saveCachedThreads(threads)
        }
    }

    func trashThread(threadID: String) async {
        guard let token = GIDSignIn.sharedInstance.currentUser?.accessToken.tokenString else {
            errorMessage = "Missing access token."
            return
        }

        do {
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/threads/\(threadID)/trash")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            _ = try await URLSession.shared.data(for: request)

            // Remove from local state and cache
            threads.removeAll { $0.threadID == threadID }
            saveCachedThreads(threads)
        } catch {
            errorMessage = "Failed to delete: \(error.localizedDescription)"
        }
    }

    func sendEmail(to: String, subject: String, body: String) async {
        guard let token = GIDSignIn.sharedInstance.currentUser?.accessToken.tokenString else {
            errorMessage = "Missing access token."
            return
        }

        isSending = true
        errorMessage = nil

        let rawMessage = [
            "To: \(to)",
            "Subject: \(subject)",
            "Content-Type: text/plain; charset=\"UTF-8\"",
            "",
            body
        ].joined(separator: "\r\n")

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

    func search(query: String) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }

        // Refresh access token before making API calls
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
            var loadedThreads: [EmailThread] = []

            for threadID in threadIDs {
                let detailURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/threads/\(threadID)?format=full")!
                var detailRequest = URLRequest(url: detailURL)
                detailRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                let (detailData, detailURLResponse) = try await URLSession.shared.data(for: detailRequest)
                if let httpResponse = detailURLResponse as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                    continue // Skip threads that fail to load
                }
                let threadDetail = try JSONDecoder().decode(GmailInboxThreadDetail.self, from: detailData)

                if let thread = Self.makeThread(from: threadDetail) {
                    loadedThreads.append(thread)
                }
            }

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

    private static func makeThread(from threadDetail: GmailInboxThreadDetail) -> EmailThread? {
        // Use the first message for display in inbox
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
        let messageCount = threadDetail.messages.count

        return EmailThread(
            threadID: threadDetail.id,
            sender: sender,
            subject: subject,
            pages: pages.isEmpty ? [snippet] : pages,
            htmlBody: body.html,
            isUnread: isUnread,
            messageCount: messageCount,
            timestamp: relativeTimestamp(from: dateValue),
            messages: [],
            debugVisibility: nil
        )
    }

    private static func makeThread(from detail: GmailMessageDetail) -> EmailThread? {
        let headers = detail.payload?.headers ?? []
        let subject = headers.first(where: { $0.name.lowercased() == "subject" })?.value ?? "(No subject)"
        let fromValue = headers.first(where: { $0.name.lowercased() == "from" })?.value ?? "Unknown Sender"
        let dateValue = headers.first(where: { $0.name.lowercased() == "date" })?.value ?? ""

        let senderName = parseSenderName(from: fromValue)
        let senderEmail = parseEmail(from: fromValue)
        let initials = initialsFromName(senderName)

        let sender = Sender(name: senderName, email: senderEmail, initials: initials)
        let snippet = detail.snippet ?? ""
        let pages = TextChunker.chunk(snippet)
        let body = extractBodies(from: detail.payload)

        let isUnread = detail.labelIds?.contains("UNREAD") ?? false

        return EmailThread(
            threadID: detail.threadId,
            sender: sender,
            subject: subject,
            pages: pages.isEmpty ? [snippet] : pages,
            htmlBody: body.html,
            isUnread: isUnread,
            messageCount: 0,
            timestamp: relativeTimestamp(from: dateValue),
            messages: [],
            debugVisibility: nil
        )
    }

    private static func parseSenderName(from value: String) -> String {
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

    private static func parseEmail(from value: String) -> String? {
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

    private static func initialsFromName(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? "?"
        let second = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + second).uppercased()
    }

    private static func relativeTimestamp(from headerValue: String) -> String {
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

    private static func parseDate(from headerValue: String) -> Date? {
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

    private static func extractBodies(from payload: GmailMessagePayload?) -> (html: String?, text: String?) {
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

    private static func decodeBase64URL(_ value: String?) -> String? {
        guard var value else { return nil }
        value = value.replacingOccurrences(of: "-", with: "+")
        value = value.replacingOccurrences(of: "_", with: "/")
        let paddedLength = ((value.count + 3) / 4) * 4
        value = value.padding(toLength: paddedLength, withPad: "=", startingAt: 0)
        guard let data = Data(base64Encoded: value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func loadCachedThreads() {
        guard let data = try? Data(contentsOf: cacheURL) else { return }
        guard let cached = try? JSONDecoder().decode([CachedThread].self, from: data) else { return }
        threads = cached.map { $0.toModel() }
    }

    private func saveCachedThreads(_ threads: [EmailThread]) {
        let cached = threads.map { CachedThread(from: $0) }
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? data.write(to: cacheURL, options: [.atomic])
    }

    private func refreshedAccessToken() async -> String? {
        guard let user = GIDSignIn.sharedInstance.currentUser else { return nil }
        return await withCheckedContinuation { continuation in
            user.refreshTokensIfNeeded { user, error in
                if let error {
                    print("Token refresh failed: \(error.localizedDescription)")
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
}

struct GmailMessageListResponse: Decodable {
    let messages: [GmailMessageRef]?
}

struct GmailMessageRef: Decodable {
    let id: String
}

struct GmailThreadListResponse: Decodable {
    let threads: [GmailThreadRef]?
}

struct GmailThreadRef: Decodable {
    let id: String
}

struct GmailInboxThreadDetail: Decodable {
    let id: String
    let messages: [GmailMessageDetail]
}

struct GmailMessageDetail: Decodable {
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
    let body: GmailMessageBody?
    let parts: [GmailMessagePart]?
}

struct GmailMessageBody: Decodable {
    let data: String?
}

struct CachedThread: Codable {
    let threadID: String?
    let senderName: String
    let senderEmail: String?
    let senderInitials: String
    let subject: String
    let pages: [String]
    let htmlBody: String?
    let isUnread: Bool
    let messageCount: Int
    let timestamp: String

    init(from thread: EmailThread) {
        threadID = thread.threadID
        senderName = thread.sender.name
        senderEmail = thread.sender.email
        senderInitials = thread.sender.initials
        subject = thread.subject
        pages = thread.pages
        htmlBody = thread.htmlBody
        isUnread = thread.isUnread
        messageCount = thread.messageCount
        timestamp = thread.timestamp
    }

    func toModel() -> EmailThread {
        EmailThread(
            threadID: threadID,
            sender: Sender(name: senderName, email: senderEmail, initials: senderInitials),
            subject: subject,
            pages: pages,
            htmlBody: htmlBody,
            isUnread: isUnread,
            messageCount: messageCount,
            timestamp: timestamp,
            messages: [],
            debugVisibility: nil
        )
    }
}
