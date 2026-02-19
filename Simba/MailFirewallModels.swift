import Foundation

struct FirewallStats: Codable {
    let review_count: Int?
    let blocked_total: Int?
    let pending_unsubscribes: Int?
    let allowlist_count: Int?
    let llm_spam: Int?
    let llm_not_spam: Int?
    let total_unsubscribed: Int?
    let blocked_today: Int?

    var reviewCount: Int { review_count ?? 0 }
    var blockedTotal: Int { blocked_total ?? 0 }
    var pendingUnsubscribes: Int { pending_unsubscribes ?? 0 }
    var allowlistCount: Int { allowlist_count ?? 0 }
    var llmSpam: Int { llm_spam ?? 0 }
    var llmNotSpam: Int { llm_not_spam ?? 0 }
    var totalUnsubscribed: Int { total_unsubscribed ?? 0 }
    var blockedToday: Int { blocked_today ?? 0 }
}

struct FirewallEmail: Codable, Identifiable {
    let id: String
    let sender: String?
    let sender_email: String?
    let subject: String?
    let snippet: String?
    let received_at: String?
    let fingerprint: String?
    let has_unsubscribe: Bool?
    let labels: [String]?
}

struct FirewallEmailDetail: Codable, Identifiable {
    let id: String
    let sender: String?
    let sender_email: String?
    let subject: String?
    let snippet: String?
    let received_at: String?
    let fingerprint: String?
    let has_unsubscribe: Bool?
    let labels: [String]?
    let body: String?
    let detection_method: String?
    let llm_decision: String?
    let llm_reason: String?
}

struct BlockedEntry: Codable, Identifiable {
    var id: String { fingerprint ?? UUID().uuidString }
    let fingerprint: String?
    let reason: String?
    let sender_email: String?
    let subject: String?
    let blocked_at: String?
    // Alternative field names the API might use
    let sender: String?
    let email: String?

    var displayEmail: String {
        sender_email ?? email ?? sender ?? fingerprint ?? "Unknown"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fingerprint = try container.decodeIfPresent(String.self, forKey: .fingerprint)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        sender_email = try container.decodeIfPresent(String.self, forKey: .sender_email)
        subject = try container.decodeIfPresent(String.self, forKey: .subject)
        blocked_at = try container.decodeIfPresent(String.self, forKey: .blocked_at)
        sender = try container.decodeIfPresent(String.self, forKey: .sender)
        email = try container.decodeIfPresent(String.self, forKey: .email)
    }

    private enum CodingKeys: String, CodingKey {
        case fingerprint, reason, sender_email, subject, blocked_at, sender, email
    }
}

struct PendingUnsubscribe: Codable, Identifiable {
    var id: String { message_id ?? UUID().uuidString }
    let message_id: String?
    let sender: String?
    let subject: String?
    let detected_at: String?
    let days_remaining: Double?
    let has_url: Bool?
    let has_mailto: Bool?

    var daysRemaining: Double { days_remaining ?? 0 }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message_id = try container.decodeIfPresent(String.self, forKey: .message_id)
        sender = try container.decodeIfPresent(String.self, forKey: .sender)
        subject = try container.decodeIfPresent(String.self, forKey: .subject)
        detected_at = try container.decodeIfPresent(String.self, forKey: .detected_at)
        has_url = try container.decodeIfPresent(Bool.self, forKey: .has_url)
        has_mailto = try container.decodeIfPresent(Bool.self, forKey: .has_mailto)
        // days_remaining might be Int or Double
        if let d = try? container.decodeIfPresent(Double.self, forKey: .days_remaining) {
            days_remaining = d
        } else if let i = try? container.decodeIfPresent(Int.self, forKey: .days_remaining) {
            days_remaining = Double(i)
        } else {
            days_remaining = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case message_id, sender, subject, detected_at, days_remaining, has_url, has_mailto
    }
}

struct AllowlistEntry: Codable, Identifiable {
    var id: String { pattern ?? UUID().uuidString }
    let pattern: String?
    let note: String?
}

struct AuditResponse: Codable {
    let entries: [AuditEntry]?
    let total: Int?
    let limit: Int?
    let offset: Int?
}

struct AuditEntry: Codable, Identifiable {
    let id: Int
    let timestamp: String?
    let action: String?
    let source: String?
    let sender_email: String?
    let subject: String?
    let reason: String?
    let message_id: String?
    let fingerprint: String?
}

struct ActionResponse: Codable {
    let success: Bool?
    let message: String?
}

enum FirewallError: LocalizedError {
    case authRequired
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .authRequired:
            return "Authentication required. Please sign in."
        case .httpError(let code):
            return "Server error (HTTP \(code))."
        }
    }
}
