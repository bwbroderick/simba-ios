import SwiftUI
import WebKit
import UIKit

struct AvatarView: View {
    let initials: String
    let isLarge: Bool

    var body: some View {
        Text(initials)
            .font(isLarge ? .caption.weight(.bold) : .caption2.weight(.bold))
            .foregroundColor(.gray)
            .frame(width: isLarge ? 36 : 30, height: isLarge ? 36 : 30)
            .background(Color(white: 0.95))
            .overlay(
                Circle()
                    .stroke(Color(white: 0.9), lineWidth: 1)
            )
            .clipShape(Circle())
    }
}

struct HeaderView: View {
    let title: String
    let showsBack: Bool
    let onBack: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            if showsBack, let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(width: 32, height: 32)
                        .background(Color(white: 0.95))
                        .clipShape(Circle())
                }
            } else {
                Text("Me")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black)
                    .clipShape(Circle())
            }

            Text(title)
                .font(.title3.weight(.bold))

            Spacer()

            if !showsBack {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundColor(.gray)
                    .padding(8)
                    .background(Color(white: 0.96))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.98))
    }
}

struct EmailCardView: View {
    let thread: EmailThread
    let isDetailView: Bool
    let isRoot: Bool
    let depth: Int
    let renderHTML: Bool
    let onThreadTap: (() -> Void)?
    var onReply: (() -> Void)?
    var onDelete: (() -> Void)?
    var onSave: (() -> Void)?
    var onCardAppear: (() -> Void)?

    var body: some View {
        let maxCardHeight: CGFloat = UIScreen.main.bounds.height * 0.6
        let pageWidth: CGFloat = UIScreen.main.bounds.width * 0.8
        let cardHeight = CardHeightCalculator.height(
            for: thread,
            isRoot: isRoot,
            depth: depth,
            maxHeight: maxCardHeight,
            pageWidth: pageWidth
        )
        let pages = CardPage.pages(for: thread, renderHTML: renderHTML)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(initials: thread.sender.initials, isLarge: isRoot)
                    .overlay(alignment: .topTrailing) {
                        if thread.isUnread {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 10, height: 10)
                                .offset(x: 2, y: -2)
                        }
                    }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(thread.sender.name)
                            .font(.caption.weight(thread.isUnread ? .bold : .medium))
                            .foregroundColor(thread.isUnread ? .black : .gray)

                        Spacer()

                        Text(thread.timestamp.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.gray.opacity(0.7))
                            .tracking(0.8)
                    }

                    Text(thread.subject)
                        .font(isRoot ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                        .foregroundColor(.black)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, 16)

            GeometryReader { geo in
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(pages) { page in
                            Group {
                                switch page.kind {
                                case .text(let text):
                                    TextCardView(text: text, isRoot: isRoot)
                                case .html(let html):
                                    HTMLCardView(html: html)
                                }
                            }
                            .frame(width: geo.size.width * 0.8, height: cardHeight)
                        }
                        Spacer(minLength: max(0, geo.size.width - (geo.size.width * 0.8) - 16))
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
            }
            .frame(height: cardHeight)

            if !isDetailView {
                HStack {
                    // Reply button
                    Button(action: { onReply?() }) {
                        Image(systemName: "arrowshape.turn.up.left")
                            .font(.body.weight(.medium))
                            .foregroundColor(.gray)
                            .frame(width: 44, height: 44)
                    }

                    Spacer()

                    // Delete button
                    Button(action: { onDelete?() }) {
                        Image(systemName: "trash")
                            .font(.body.weight(.medium))
                            .foregroundColor(.red.opacity(0.8))
                            .frame(width: 44, height: 44)
                    }

                    Spacer()

                    // Thread button with badge
                    Button(action: { onThreadTap?() }) {
                        Image(systemName: "bubble.left")
                            .font(.body.weight(.medium))
                            .foregroundColor(thread.threadID != nil ? .gray : .gray.opacity(0.3))
                            .frame(width: 44, height: 44)
                            .overlay(alignment: .topTrailing) {
                                if thread.messageCount > 0 {
                                    Text("\(thread.messageCount)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(4)
                                        .background(Color.blue)
                                        .clipShape(Circle())
                                        .offset(x: 8, y: 0)
                                }
                            }
                    }
                    .disabled(thread.threadID == nil)
                }
                .padding(.horizontal, depth > 0 ? 44 : 58)
            }
        }
        .padding(.vertical, isRoot ? 12 : 8)
        .background(Color.white)
        .overlay(alignment: .topTrailing) {
            if let debug = thread.debugVisibility {
                Text(debug)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.7))
                    .clipShape(Capsule())
                    .padding(.top, 6)
                    .padding(.trailing, 10)
            }
        }
        .overlay(
            Rectangle()
                .fill(Color(white: 0.95))
                .frame(height: 1),
            alignment: .bottom
        )
        .padding(.leading, depth > 0 ? 24 : 0)
        .overlay(
            depth > 0 ? AnyView(
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundColor(.gray.opacity(0.5))
                    .offset(x: -8, y: -4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            ) : AnyView(EmptyView())
        )
        .onAppear {
            onCardAppear?()
        }
    }
}

struct TextCardView: View {
    let text: String
    let isRoot: Bool

    var body: some View {
        VStack {
            Text(text)
                .font(isRoot ? .body : .subheadline)
                .foregroundColor(.gray.opacity(0.9))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.97))
        .cornerRadius(16)
    }
}

struct HTMLCardView: View {
    let html: String
    @StateObject private var renderer = HTMLSnapshotRenderer()

    var body: some View {
        Group {
            if let image = renderer.snapshot {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color(white: 0.97))
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
            }
        }
        .background(Color(white: 0.97))
        .cornerRadius(16)
        .onAppear {
            let width = UIScreen.main.bounds.width * 0.8 - 32
            renderer.render(html: html, width: width)
        }
    }
}

class HTMLSnapshotRenderer: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var snapshot: UIImage?

    private static var cache: [String: UIImage] = [:]
    private static var pending: Set<String> = []

    private var webView: WKWebView?
    private var currentKey: String?
    private var targetSize: CGSize = .zero

    func render(html: String, width: CGFloat) {
        let key = "\(html.hashValue)_\(Int(width))"

        if let cached = Self.cache[key] {
            snapshot = cached
            return
        }

        guard !Self.pending.contains(key) else { return }
        Self.pending.insert(key)
        currentKey = key
        targetSize = CGSize(width: width, height: 300)

        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true

        let wv = WKWebView(frame: CGRect(origin: .zero, size: targetSize), configuration: config)
        wv.navigationDelegate = self
        wv.isOpaque = false
        wv.backgroundColor = UIColor(white: 0.97, alpha: 1.0)
        wv.scrollView.isScrollEnabled = false

        webView = wv

        let styledHTML = """
        <!DOCTYPE html>
        <html>
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=\(Int(width)), initial-scale=1.0, maximum-scale=1.0">
            <style>
              * { box-sizing: border-box; }
              html, body { margin: 0; padding: 0; width: \(Int(width))px; overflow: hidden; }
              body { font-family: -apple-system, Helvetica, Arial, sans-serif; font-size: 15px; line-height: 1.5; color: #222; padding: 16px; background: #f7f7f7; }
              img { max-width: 100%; height: auto; display: block; }
              a { color: #111; }
              pre, code { white-space: pre-wrap; word-wrap: break-word; }
              table { max-width: 100%; }
            </style>
          </head>
          <body>\(html)</body>
        </html>
        """

        wv.loadHTMLString(styledHTML, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.takeSnapshot()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        cleanup()
    }

    private func takeSnapshot() {
        guard let wv = webView, let key = currentKey else { return }

        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: targetSize)

        wv.takeSnapshot(with: config) { [weak self] image, error in
            guard let self = self else { return }
            if let image = image {
                Self.cache[key] = image
                DispatchQueue.main.async {
                    self.snapshot = image
                }
            }
            self.cleanup()
        }
    }

    private func cleanup() {
        if let key = currentKey {
            Self.pending.remove(key)
        }
        webView?.navigationDelegate = nil
        webView = nil
        currentKey = nil
    }
}

struct BottomNavView: View {
    let isUnreadOnly: Bool
    let onUnreadToggle: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "tray")
                .font(.title3.weight(.semibold))
                .foregroundColor(.black)
                .frame(width: 44, height: 44)
            Spacer()
            Button(action: onUnreadToggle) {
                Image(systemName: isUnreadOnly ? "envelope.badge.fill" : "envelope.badge")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(isUnreadOnly ? .black : .gray.opacity(0.5))
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Image(systemName: "star")
                .font(.title3.weight(.semibold))
                .foregroundColor(.gray.opacity(0.5))
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 48)
        .padding(.top, 12)
        .padding(.bottom, 34)
        .background(Color.white)
        .overlay(
            Rectangle()
                .fill(Color(white: 0.92))
                .frame(height: 1),
            alignment: .top
        )
    }
}

struct FloatingComposeButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "square.and.pencil")
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(Color.black)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
        }
    }
}

struct ReplyBarView: View {
    let name: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                AvatarView(initials: "Me", isLarge: false)

                Text("Reply to \(name)...")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(white: 0.95))
                    .cornerRadius(20)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white)
            .overlay(
                Rectangle()
                    .fill(Color(white: 0.92))
                    .frame(height: 1),
                alignment: .top
            )
        }
        .buttonStyle(.plain)
    }
}

struct ComposeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var to = ""
    @State private var subject = ""
    @State private var messageBody = ""

    let isSending: Bool
    let onSend: (String, String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("To")) {
                    TextField("email@example.com", text: $to)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }

                Section(header: Text("Subject")) {
                    TextField("Subject", text: $subject)
                }

                Section(header: Text("Message")) {
                    TextEditor(text: $messageBody)
                        .frame(minHeight: 160)
                }
            }
            .navigationTitle("New Email")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSending ? "Sending..." : "Send") {
                        onSend(to, subject, messageBody)
                        if !isSending {
                            dismiss()
                        }
                    }
                    .disabled(isSending || to.isEmpty || subject.isEmpty || messageBody.isEmpty)
                }
            }
        }
    }
}

struct ReplyComposeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var to: String
    @State private var subject: String
    @State private var messageBody = ""

    let isSending: Bool
    let onSend: (String, String, String) -> Void

    init(to: String, subject: String, isSending: Bool, onSend: @escaping (String, String, String) -> Void) {
        self._to = State(initialValue: to)
        self._subject = State(initialValue: subject)
        self.isSending = isSending
        self.onSend = onSend
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("To")) {
                    TextField("email@example.com", text: $to)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }

                Section(header: Text("Subject")) {
                    TextField("Subject", text: $subject)
                }

                Section(header: Text("Message")) {
                    TextEditor(text: $messageBody)
                        .frame(minHeight: 160)
                }
            }
            .navigationTitle("Reply")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSending ? "Sending..." : "Send") {
                        onSend(to, subject, messageBody)
                        if !isSending {
                            dismiss()
                        }
                    }
                    .disabled(isSending || to.isEmpty || subject.isEmpty || messageBody.isEmpty)
                }
            }
        }
    }
}

struct CardPage: Identifiable {
    enum Kind {
        case text(String)
        case html(String)
    }

    let id = UUID()
    let kind: Kind

    static func pages(
        for thread: EmailThread,
        renderHTML: Bool
    ) -> [CardPage] {
        var pages: [CardPage] = []

        if renderHTML, let html = thread.htmlBody, !html.isEmpty {
            pages.append(contentsOf: HTMLChunker.chunk(html).map {
                CardPage(kind: .html($0))
            })
        } else {
            pages.append(contentsOf: thread.pages.map { CardPage(kind: .text($0)) })
        }

        return pages
    }
}

enum HTMLChunker {
    static func chunk(_ html: String, maxLength: Int = 1400) -> [String] {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxLength { return [trimmed] }

        let parts = splitByParagraphs(trimmed)
        if parts.count <= 1 {
            return hardChunk(trimmed, maxLength: maxLength)
        }

        var chunks: [String] = []
        var current = ""

        for part in parts {
            if (current + part).count > maxLength {
                if !current.isEmpty { chunks.append(current) }
                current = part
            } else {
                current += part
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }

    private static func splitByParagraphs(_ html: String) -> [String] {
        let separator = "</p>"
        let rawParts = html.components(separatedBy: separator)
        if rawParts.count <= 1 { return [html] }
        return rawParts.map { part in
            part.trimmingCharacters(in: .whitespacesAndNewlines) + separator
        }
    }

    private static func hardChunk(_ html: String, maxLength: Int) -> [String] {
        var chunks: [String] = []
        var currentIndex = html.startIndex

        while currentIndex < html.endIndex {
            let endIndex = html.index(currentIndex, offsetBy: maxLength, limitedBy: html.endIndex) ?? html.endIndex
            chunks.append(String(html[currentIndex..<endIndex]))
            currentIndex = endIndex
        }

        return chunks
    }
}

enum CardHeightCalculator {
    static func height(
        for thread: EmailThread,
        isRoot: Bool,
        depth: Int,
        maxHeight: CGFloat,
        pageWidth: CGFloat
    ) -> CGFloat {
        let minHeight: CGFloat = isRoot ? 140 : 120
        let textWidth = max(pageWidth - 32, 120)

        if let html = thread.htmlBody, !html.isEmpty {
            return maxHeight
        }

        let font = UIFont.systemFont(ofSize: isRoot ? 17 : 15)
        let heights = thread.pages.map { textHeight($0, font: font, width: textWidth) + 32 }
        let maxTextHeight = heights.max() ?? minHeight

        return min(maxHeight, max(minHeight, maxTextHeight))
    }

    private static func textHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        let rect = text.boundingRect(
            with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return ceil(rect.height)
    }
}

struct GmailConnectCard: View {
    let onConnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect Gmail")
                .font(.headline.weight(.bold))
            Text("Sign in to show your real inbox. Read-only access for Phase 1.")
                .font(.subheadline)
                .foregroundColor(.gray)
            Button(action: onConnect) {
                HStack(spacing: 8) {
                    Image(systemName: "envelope")
                    Text("Sign in with Google")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundColor(.white)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(Color.black)
                .cornerRadius(18)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.97))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color(white: 0.9), lineWidth: 1)
        )
    }
}
