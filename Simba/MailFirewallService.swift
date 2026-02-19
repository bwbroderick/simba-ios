import Foundation

@MainActor
final class MailFirewallService: ObservableObject {
    static let shared = MailFirewallService()

    @Published var isAuthenticated = false
    @Published var showAuthWebView = false

    private let baseURL = "https://api.ai-simba.com/api/v1"
    private let tokenKey = "CF_Authorization_JWT"

    private var token: String? {
        didSet {
            isAuthenticated = token != nil
        }
    }

    private init() {
        token = UserDefaults.standard.string(forKey: tokenKey)
        isAuthenticated = token != nil
    }

    func setToken(_ jwt: String) {
        token = jwt
        UserDefaults.standard.set(jwt, forKey: tokenKey)
    }

    func clearToken() {
        token = nil
        UserDefaults.standard.removeObject(forKey: tokenKey)
        // Also clear Cloudflare cookies from URLSession storage
        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies where cookie.domain.contains("ai-simba.com") {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
    }

    // MARK: - Networking

    private func authorizedRequest(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        // Let URLSession's cookie storage handle cookies (cf_clearance, etc.)
        // but also ensure CF_Authorization is included
        request.httpShouldHandleCookies = true
        if let token {
            // Set CF_Authorization as a cookie in the shared storage so it's sent
            // alongside cf_clearance and other Cloudflare cookies
            if let cookie = HTTPCookie(properties: [
                .name: "CF_Authorization",
                .value: token,
                .domain: "api.ai-simba.com",
                .path: "/",
                .secure: "TRUE"
            ]) {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
        return request
    }

    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FirewallError.httpError(0)
        }

        let status = httpResponse.statusCode
        print("[MailFirewall] \(request.httpMethod ?? "GET") \(request.url?.path ?? "") → \(status)")

        // URLSession auto-follows redirects, so check if we ended up on a different host
        if let finalURL = httpResponse.url,
           let requestHost = request.url?.host,
           let responseHost = finalURL.host,
           responseHost != requestHost {
            print("[MailFirewall] Redirected to \(responseHost) — auth required")
            clearToken()
            throw FirewallError.authRequired
        }

        // Cloudflare Access/challenge responses
        if [302, 401, 403, 530].contains(status) {
            clearToken()
            throw FirewallError.authRequired
        }
        guard (200...299).contains(status) else {
            throw FirewallError.httpError(status)
        }
        // Detect HTML responses (Cloudflare login/challenge page served as 200)
        if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
           contentType.contains("text/html") {
            clearToken()
            throw FirewallError.authRequired
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let preview = String(data: data.prefix(500), encoding: .utf8) ?? "(non-utf8)"
            print("[MailFirewall] Decode error for \(T.self): \(error)\nResponse preview: \(preview)")
            throw error
        }
    }

    private func performAction(_ request: URLRequest) async throws -> ActionResponse {
        try await performRequest(request)
    }

    // MARK: - API Methods

    func fetchStats() async throws -> FirewallStats {
        let url = URL(string: "\(baseURL)/stats")!
        let request = authorizedRequest(url: url)
        return try await performRequest(request)
    }

    func fetchReviewEmails() async throws -> [FirewallEmail] {
        let url = URL(string: "\(baseURL)/review")!
        let request = authorizedRequest(url: url)
        return try await performRequest(request)
    }

    func fetchBlocked() async throws -> [BlockedEntry] {
        let url = URL(string: "\(baseURL)/blocked")!
        let request = authorizedRequest(url: url)
        return try await performRequest(request)
    }

    func fetchPending() async throws -> [PendingUnsubscribe] {
        let url = URL(string: "\(baseURL)/pending")!
        let request = authorizedRequest(url: url)
        return try await performRequest(request)
    }

    func fetchAllowlist() async throws -> [AllowlistEntry] {
        let url = URL(string: "\(baseURL)/allowlist")!
        let request = authorizedRequest(url: url)
        return try await performRequest(request)
    }

    func fetchAuditLog(limit: Int = 50, offset: Int = 0) async throws -> AuditResponse {
        let url = URL(string: "\(baseURL)/audit?limit=\(limit)&offset=\(offset)")!
        let request = authorizedRequest(url: url)
        return try await performRequest(request)
    }

    func approveEmail(id: String) async throws -> ActionResponse {
        let url = URL(string: "\(baseURL)/review/\(id)/approve")!
        let request = authorizedRequest(url: url, method: "POST")
        return try await performAction(request)
    }

    func approveOnce(id: String) async throws -> ActionResponse {
        let url = URL(string: "\(baseURL)/review/\(id)/approve-once")!
        let request = authorizedRequest(url: url, method: "POST")
        return try await performAction(request)
    }

    func rejectEmail(id: String) async throws -> ActionResponse {
        let url = URL(string: "\(baseURL)/review/\(id)/reject")!
        let request = authorizedRequest(url: url, method: "POST")
        return try await performAction(request)
    }

    func unblock(fingerprint: String) async throws -> ActionResponse {
        let url = URL(string: "\(baseURL)/blocked/\(fingerprint)")!
        let request = authorizedRequest(url: url, method: "DELETE")
        return try await performAction(request)
    }

    func cancelPending(messageId: String) async throws -> ActionResponse {
        let url = URL(string: "\(baseURL)/pending/\(messageId)/cancel")!
        let request = authorizedRequest(url: url, method: "POST")
        return try await performAction(request)
    }

    func executePending(messageId: String) async throws -> ActionResponse {
        let url = URL(string: "\(baseURL)/pending/\(messageId)/execute")!
        let request = authorizedRequest(url: url, method: "POST")
        return try await performAction(request)
    }

    func addAllowlistEntry(pattern: String, note: String?) async throws -> ActionResponse {
        let url = URL(string: "\(baseURL)/allowlist")!
        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: String] = ["pattern": pattern]
        if let note, !note.isEmpty {
            body["note"] = note
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await performAction(request)
    }

    func removeAllowlistEntry(pattern: String) async throws -> ActionResponse {
        let encoded = pattern.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pattern
        let url = URL(string: "\(baseURL)/allowlist/\(encoded)")!
        let request = authorizedRequest(url: url, method: "DELETE")
        return try await performAction(request)
    }
}
