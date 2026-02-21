import Foundation
import GoogleSignIn
import OSLog

@MainActor
final class GmailThreadLoader: ObservableObject {
    @Published var messages: [EmailMessage] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(threadID: String) async {
        guard let token = GIDSignIn.sharedInstance.currentUser?.accessToken.tokenString else {
            errorMessage = "Missing access token."
            return
        }

        Logger.network.info("Loading thread \(threadID, privacy: .private)")
        isLoading = true
        errorMessage = nil

        do {
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/threads/\(threadID)?format=full")!
            var request = URLRequest(url: url)
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, _) = try await URLSession.shared.data(for: request)
            let detail = try JSONDecoder().decode(GmailThreadDetail.self, from: data)

            let parsed = detail.messages.enumerated().compactMap { index, message in
                GmailMessageParser.makeMessage(from: message, isRoot: index == 0)
            }

            messages = parsed
        } catch {
            Logger.network.error("Thread load error: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct GmailThreadDetail: Decodable {
    let messages: [GmailThreadMessage]
}

struct GmailThreadMessage: Decodable {
    let id: String?
    let snippet: String?
    let payload: GmailMessagePayload?
}

enum GmailMessageParser {
    static func makeMessage(from detail: GmailThreadMessage, isRoot: Bool) -> EmailMessage? {
        let headers = detail.payload?.headers ?? []
        let subject = headers.first(where: { $0.name.lowercased() == "subject" })?.value ?? "(No subject)"
        let fromValue = headers.first(where: { $0.name.lowercased() == "from" })?.value ?? "Unknown Sender"
        let dateValue = headers.first(where: { $0.name.lowercased() == "date" })?.value ?? ""

        let senderName = GmailMessageParser.parseSenderName(from: fromValue)
        let senderEmail = GmailMessageParser.parseEmail(from: fromValue)
        let initials = GmailMessageParser.initialsFromName(senderName)
        let sender = Sender(name: senderName, email: senderEmail, initials: initials)

        let snippet = detail.snippet ?? ""
        let pages = TextChunker.chunk(snippet)
        let body = GmailMessageParser.extractBodies(from: detail.payload)

        let messageId = detail.id ?? ""
        let attachments = GmailMessageParser.extractAttachments(from: detail.payload, messageId: messageId)

        return EmailMessage(
            messageId: detail.id,
            sender: sender,
            subject: subject,
            pages: pages.isEmpty ? [snippet] : pages,
            htmlBody: body.html,
            timestamp: GmailMessageParser.relativeTimestamp(from: dateValue),
            isRoot: isRoot,
            depth: 0,
            attachments: attachments
        )
    }

    static func extractAttachments(from payload: GmailMessagePayload?, messageId: String) -> [EmailAttachment] {
        guard let payload else { return [] }
        var attachments: [EmailAttachment] = []

        func walk(_ part: GmailMessagePart) {
            if let filename = part.filename, !filename.isEmpty,
               let attachmentId = part.body?.attachmentId {
                let size = part.body?.size ?? 0
                attachments.append(EmailAttachment(
                    filename: filename,
                    mimeType: part.mimeType ?? "application/octet-stream",
                    size: size,
                    attachmentId: attachmentId,
                    messageId: messageId
                ))
            }
            part.parts?.forEach { walk($0) }
        }

        if let parts = payload.parts {
            parts.forEach { walk($0) }
        }

        return attachments
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
}
