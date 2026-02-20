import Foundation
import SwiftUI

@MainActor
class ContactStore: ObservableObject {
    static let shared = ContactStore()

    struct Contact: Identifiable {
        let id = UUID()
        let name: String
        let email: String
        let initials: String
    }

    @Published var contacts: [Contact] = []

    func extract(from threads: [EmailThread]) {
        var seen: Set<String> = []
        var result: [Contact] = []
        for thread in threads {
            guard let email = thread.sender.email?.lowercased(),
                  !seen.contains(email) else { continue }
            seen.insert(email)
            result.append(Contact(
                name: thread.sender.name,
                email: email,
                initials: thread.sender.initials
            ))
        }
        contacts = result
    }

    func suggestions(for query: String) -> [Contact] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        return contacts.filter {
            $0.name.lowercased().contains(q) || $0.email.contains(q)
        }.prefix(5).map { $0 }
    }
}

struct Sender: Identifiable {
    let id = UUID()
    let name: String
    let email: String?
    let initials: String
}

struct EmailAttachment: Identifiable {
    let id = UUID()
    let filename: String
    let mimeType: String
    let size: Int
    let attachmentId: String
    let messageId: String

    var fileExtension: String {
        let components = filename.split(separator: ".")
        return components.count > 1 ? String(components.last!) : ""
    }

    var iconName: String {
        let ext = fileExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext"
        case "jpg", "jpeg", "png", "gif", "heic", "webp": return "photo"
        case "doc", "docx": return "doc.text"
        case "xls", "xlsx": return "tablecells"
        case "ppt", "pptx": return "rectangle.on.rectangle"
        case "zip", "tar", "gz", "rar": return "doc.zipper"
        case "mp3", "wav", "m4a", "aac": return "music.note"
        case "mp4", "mov", "avi": return "film"
        case "txt": return "doc.plaintext"
        case "csv": return "tablecells"
        default: return "doc"
        }
    }

    var formattedSize: String {
        if size < 1024 {
            return "\(size) B"
        } else if size < 1024 * 1024 {
            return String(format: "%.1f KB", Double(size) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(size) / (1024.0 * 1024.0))
        }
    }
}

struct EmailMessage: Identifiable {
    let id = UUID()
    let messageId: String?
    let sender: Sender
    let subject: String
    let pages: [String]
    let htmlBody: String?
    let timestamp: String
    let isRoot: Bool
    let depth: Int
    let attachments: [EmailAttachment]
}

struct EmailThread: Identifiable {
    let id = UUID()
    let threadID: String?
    let sender: Sender
    let subject: String
    let pages: [String]
    let htmlBody: String?
    let isUnread: Bool
    let isStarred: Bool
    let messageCount: Int
    let timestamp: String
    let messages: [EmailMessage]
    let labelIds: [String]
    let attachments: [EmailAttachment]
    let debugVisibility: String?

    init(
        threadID: String? = nil,
        sender: Sender,
        subject: String,
        pages: [String],
        htmlBody: String? = nil,
        isUnread: Bool = false,
        isStarred: Bool = false,
        messageCount: Int = 0,
        timestamp: String = "",
        messages: [EmailMessage] = [],
        labelIds: [String] = [],
        attachments: [EmailAttachment] = [],
        debugVisibility: String? = nil
    ) {
        self.threadID = threadID
        self.sender = sender
        self.subject = subject
        self.pages = pages
        self.htmlBody = htmlBody
        self.isUnread = isUnread
        self.isStarred = isStarred
        self.messageCount = messageCount
        self.timestamp = timestamp
        self.messages = messages
        self.labelIds = labelIds
        self.attachments = attachments
        self.debugVisibility = debugVisibility
    }
}

enum TextChunker {
    static func chunk(_ text: String) -> [String] {
        if text.count < 80 { return [text] }
        let sentenceRegex = try? NSRegularExpression(pattern: "[^.!?]+[.!?]+", options: [])
        let range = NSRange(text.startIndex..., in: text)
        let matches = sentenceRegex?.matches(in: text, options: [], range: range) ?? []
        let sentences: [String] = matches.isEmpty
            ? [text]
            : matches.compactMap { match in
                guard let range = Range(match.range, in: text) else { return nil }
                return String(text[range])
            }

        var chunks: [String] = []
        var current = ""

        for sentence in sentences {
            if (current + sentence).count > 120 {
                if !current.isEmpty { chunks.append(current.trimmingCharacters(in: .whitespaces)) }
                current = sentence
            } else {
                current += current.isEmpty ? sentence : " " + sentence
            }
        }

        if !current.isEmpty {
            chunks.append(current.trimmingCharacters(in: .whitespaces))
        }

        return chunks
    }
}

enum SampleData {
    static let threads: [EmailThread] = {
        let senders: [Sender] = [
            Sender(name: "Sarah Chen", email: "sarah.chen@example.com", initials: "SC"),
            Sender(name: "Marcus O'Neil", email: "marcus.oneil@example.com", initials: "MO"),
            Sender(name: "Priya Patel", email: "priya.patel@example.com", initials: "PP"),
            Sender(name: "Alex Rivera", email: "alex.rivera@example.com", initials: "AR"),
            Sender(name: "Newsletter Bot", email: "newsletter@example.com", initials: "NB")
        ]

        let subjects = [
            "Q4 Design Review - Final Thoughts",
            "Project Alpha: Status Update",
            "Invitation: Lunch & Learn",
            "Your subscription is renewing soon",
            "RE: The new prototypes look amazing"
        ]

        let bodies = [
            "Hi team, I've reviewed the latest deck. The typography is looking sharper, but I'm still concerned about the contrast ratios on the dark mode mockups. Can we iterate on the secondary palette? I've attached some references that might help guide the direction. One more thought: the spacing in the hero module feels tight, especially on smaller screens. If we loosen that and bump the line height, it will breathe. Also, the data chart labels could use more padding so the values don't collide. I'd love to review another pass this afternoon if possible.",
            "Quick update on where we stand. The backend API is 90% complete. We hit a snag with the database migration but resolved it late last night. The frontend team can start integration testing tomorrow.",
            "Don't forget the Lunch & Learn today at 12:30 PM in the main conference room. Pizza will be provided. We'll cover the new design system components and how to use them.",
            "This is a reminder that your Pro subscription will renew on Nov 15th. No action is needed if you want to continue. To update your payment method or cancel, visit your account settings.",
            "I agree with the feedback. The interactions feel very fluid now. One note: the animation curve on the modal open feels slightly too bouncy. Maybe tone down the spring stiffness. Otherwise, this is ready."
        ]

        var threads: [EmailThread] = []

        for index in 0..<8 {
            let sender = senders[index % senders.count]
            let subject = subjects[index % subjects.count]
            let body = bodies[index % bodies.count]

            let isThread = index % 3 == 0
            let isNestedScenario = index == 1
            let messageCount = isNestedScenario ? 3 : (isThread ? Int.random(in: 2...5) : 0)

            var messages: [EmailMessage] = []

            if isNestedScenario {
                messages.append(EmailMessage(
                    messageId: nil,
                    sender: sender,
                    subject: subject,
                    pages: TextChunker.chunk(body),
                    htmlBody: nil,
                    timestamp: "10:30 AM",
                    isRoot: true,
                    depth: 0,
                    attachments: []
                ))
                messages.append(EmailMessage(
                    messageId: nil,
                    sender: senders[(index + 1) % senders.count],
                    subject: "RE: \(subject)",
                    pages: TextChunker.chunk("That's great news! Do we have a fallback plan if the integration testing reveals issues?"),
                    htmlBody: nil,
                    timestamp: "10:45 AM",
                    isRoot: false,
                    depth: 0,
                    attachments: []
                ))
                messages.append(EmailMessage(
                    messageId: nil,
                    sender: sender,
                    subject: "RE: \(subject)",
                    pages: TextChunker.chunk("Yes, we have a rollback script ready. If we see >1% error rate, we revert immediately."),
                    htmlBody: nil,
                    timestamp: "10:52 AM",
                    isRoot: false,
                    depth: 1,
                    attachments: []
                ))
            } else if isThread {
                messages.append(EmailMessage(
                    messageId: nil,
                    sender: sender,
                    subject: subject,
                    pages: TextChunker.chunk(body),
                    htmlBody: nil,
                    timestamp: "10:30 AM",
                    isRoot: true,
                    depth: 0,
                    attachments: []
                ))
                messages.append(EmailMessage(
                    messageId: nil,
                    sender: senders[(index + 1) % senders.count],
                    subject: "RE: \(subject)",
                    pages: TextChunker.chunk("Looks good to me."),
                    htmlBody: nil,
                    timestamp: "11:00 AM",
                    isRoot: false,
                    depth: 0,
                    attachments: []
                ))
            }

            threads.append(EmailThread(
                threadID: nil,
                sender: sender,
                subject: subject,
                pages: TextChunker.chunk(body),
                htmlBody: nil,
                isUnread: index % 2 == 0,
                isStarred: index % 4 == 0,
                messageCount: messageCount,
                timestamp: isNestedScenario ? "Now" : "2h",
                messages: messages,
                debugVisibility: nil
            ))
        }

        return threads
    }()
}
