import SwiftUI
import WebKit
import UIKit
import Combine

enum DebugSettings {
    static var showHTMLDebug = false
}

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
    var onMeTap: (() -> Void)?

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
                Button(action: { onMeTap?() }) {
                    Text("Me")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.black)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Text(title)
                .font(.title3.weight(.bold))

            Spacer()

            if !showsBack {
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.98))
    }
}

struct SideDrawerView: View {
    @Binding var isPresented: Bool
    let onSignOut: () -> Void
    var onBugReport: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Settings")
                    .font(.headline.weight(.semibold))
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.gray)
                        .frame(width: 28, height: 28)
                        .background(Color(white: 0.95))
                        .clipShape(Circle())
                }
            }

            Rectangle()
                .fill(Color(white: 0.92))
                .frame(height: 1)

            Button(action: { onBugReport?() }) {
                HStack(spacing: 10) {
                    Image(systemName: "ladybug")
                        .font(.body.weight(.semibold))
                    Text("Report Bug")
                        .font(.body.weight(.semibold))
                }
                .foregroundColor(.black.opacity(0.8))
            }

            Button(action: onSignOut) {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.body.weight(.semibold))
                    Text("Sign out")
                        .font(.body.weight(.semibold))
                }
                .foregroundColor(.red.opacity(0.9))
            }

            Spacer()
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(white: 0.98))
        .overlay(
            Rectangle()
                .fill(Color(white: 0.9))
                .frame(width: 1),
            alignment: .trailing
        )
    }
}

struct EmailCardView: View {
    let thread: EmailThread
    let isDetailView: Bool
    let isRoot: Bool
    let depth: Int
    let renderHTML: Bool
    let onThreadTap: (() -> Void)?
    var onCardTap: ((Double) -> Void)?  // Passes scroll fraction (0.0 to 1.0)
    var onReply: (() -> Void)?
    var onForward: (() -> Void)?
    var onDelete: (() -> Void)?
    var onSave: (() -> Void)?
    var onCardAppear: (() -> Void)?

    @State private var visiblePageID: Int?
    @State private var htmlPageCount: Int = 1

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
                let cardWidth = geo.size.width * 0.8
                if renderHTML, let html = thread.htmlBody, !html.isEmpty {
                    // Use multi-page HTML rendering
                    HTMLContentView(
                        html: html,
                        cardWidth: cardWidth,
                        cardHeight: cardHeight,
                        visiblePageID: $visiblePageID,
                        onPageCountChanged: { count in
                            htmlPageCount = count
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let fraction = calculateScrollFraction(isHTML: true)
                        onCardTap?(fraction)
                    }
                } else {
                    // Use text pages
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(Array(thread.pages.enumerated()), id: \.offset) { index, text in
                                TextCardView(text: text, isRoot: isRoot)
                                    .frame(width: cardWidth, height: cardHeight)
                                    .id(index)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollPosition(id: $visiblePageID)
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.viewAligned)
                    .contentMargins(.horizontal, 16, for: .scrollContent)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let fraction = calculateScrollFraction(isHTML: false)
                        onCardTap?(fraction)
                    }
                }
            }
            .frame(height: cardHeight)
            .padding(.vertical, 4)

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

                    // Forward button
                    Button(action: { onForward?() }) {
                        Image(systemName: "arrowshape.turn.up.right")
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
                            .foregroundColor(thread.messageCount > 1 ? .gray : .gray.opacity(0.3))
                            .frame(width: 44, height: 44)
                            .overlay(alignment: .topTrailing) {
                                Text("\(thread.messageCount)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(4)
                                    .background(thread.messageCount > 1 ? Color.blue : Color.gray.opacity(0.4))
                                    .clipShape(Circle())
                                    .offset(x: 8, y: 0)
                            }
                    }
                    .disabled(thread.messageCount <= 1)
                }
                .padding(.horizontal, depth > 0 ? 44 : 48)
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

    private func calculateScrollFraction(isHTML: Bool) -> Double {
        let currentPage = visiblePageID ?? 0
        let totalPages = isHTML ? htmlPageCount : thread.pages.count
        guard totalPages > 1 else { return 0.0 }
        return Double(currentPage) / Double(totalPages - 1)
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

// Displays HTML content as horizontally scrollable page cards
struct HTMLContentView: View {
    let html: String
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    @Binding var visiblePageID: Int?
    var onPageCountChanged: ((Int) -> Void)?
    @StateObject private var renderer = HTMLSnapshotRenderer()

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                if renderer.pages.isEmpty {
                    // Show loading placeholder
                    Rectangle()
                        .fill(Color(white: 0.97))
                        .frame(width: cardWidth, height: cardHeight)
                        .cornerRadius(16)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.8)
                        )
                        .id(0)
                } else {
                    ForEach(Array(renderer.pages.enumerated()), id: \.offset) { index, image in
                        ZStack(alignment: .topLeading) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: cardWidth, height: cardHeight, alignment: .top)

                            if DebugSettings.showHTMLDebug {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("page \(index + 1)/\(renderer.pages.count)")
                                    Text("HTML: \(html.count) chars")
                                }
                                .font(.caption2.monospaced())
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(6)
                                .padding(8)
                            }
                        }
                        .frame(width: cardWidth, height: cardHeight)
                        .background(Color(white: 0.97))
                        .cornerRadius(16)
                        .id(index)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $visiblePageID)
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .onAppear {
            renderer.render(html: html, size: CGSize(width: cardWidth, height: cardHeight))
        }
        .onChange(of: renderer.pages.count) { _, newCount in
            onPageCountChanged?(newCount)
        }
    }
}

class HTMLSnapshotRenderer: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var pages: [UIImage] = []
    @Published var isLoading = true

    private static let pendingQueue = DispatchQueue(label: "com.simba.pending")
    private static var _pending: Set<String> = []

    private static func isPending(_ key: String) -> Bool {
        pendingQueue.sync { _pending.contains(key) }
    }

    private static func addPending(_ key: String) -> Bool {
        pendingQueue.sync {
            guard !_pending.contains(key) else { return false }
            _pending.insert(key)
            return true
        }
    }

    private static func removePending(_ key: String) {
        pendingQueue.async { _pending.remove(key) }
    }

    private var webView: WKWebView?
    private var baseKey: String?
    private var pageSize: CGSize = .zero
    private var expectedPages: Int = 0
    private var currentPageIndex: Int = 0
    private var cacheObserver: NSObjectProtocol?

    func render(html: String, size: CGSize) {
        let key = "\(html.hashValue)_\(Int(size.width))x\(Int(size.height))"
        baseKey = key
        pageSize = size

        // Check if already fully cached
        if let cached = HTMLSnapshotCache.shared.images(for: key) {
            pages = cached
            isLoading = false
            return
        }

        // Listen for completion notifications
        if cacheObserver == nil {
            cacheObserver = NotificationCenter.default.addObserver(
                forName: HTMLSnapshotCache.didCompleteNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self = self,
                      let completedKey = notification.userInfo?["baseKey"] as? String,
                      completedKey == self.baseKey,
                      let images = HTMLSnapshotCache.shared.images(for: completedKey) else { return }
                self.pages = images
                self.isLoading = false
            }
        }

        guard Self.addPending(key) else {
            // Another renderer is working on this - we'll get notified when done
            return
        }

        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true

        // Create WebView with full width but allow content to determine height
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: size.width, height: 10000), configuration: config)
        wv.navigationDelegate = self
        wv.isOpaque = false
        wv.backgroundColor = UIColor(white: 0.97, alpha: 1.0)
        wv.scrollView.isScrollEnabled = true

        webView = wv

        // Don't constrain body height - let content flow naturally
        let styledHTML = """
        <!DOCTYPE html>
        <html>
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=\(Int(size.width)), initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
              * { box-sizing: border-box; max-width: 100% !important; }
              html, body { margin: 0; padding: 0; width: \(Int(size.width))px; overflow-x: hidden; }
              body { font-family: -apple-system, Helvetica, Arial, sans-serif; font-size: 15px; line-height: 1.5; color: #222; padding: 16px; background: #f7f7f7; word-wrap: break-word; overflow-wrap: break-word; }
              img { max-width: 100% !important; width: auto !important; height: auto !important; display: block; }
              a { color: #111; }
              pre, code { white-space: pre-wrap; word-wrap: break-word; max-width: 100%; overflow-x: hidden; }
              table { max-width: 100% !important; width: 100% !important; table-layout: fixed; border-collapse: collapse; }
              td, th { word-wrap: break-word; overflow-wrap: break-word; }
              div, span, p { max-width: 100% !important; }
            </style>
          </head>
          <body>\(html)</body>
        </html>
        """

        wv.loadHTMLString(styledHTML, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Wait for rendering, then measure content height
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.measureAndCapture()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        cleanup()
    }

    private func measureAndCapture() {
        guard let wv = webView else { return }

        // Get the actual content width and height
        let measureJS = """
        (function() {
            var contentWidth = document.body.scrollWidth;
            var contentHeight = document.body.scrollHeight;
            return { width: contentWidth, height: contentHeight };
        })()
        """

        wv.evaluateJavaScript(measureJS) { [weak self] result, error in
            guard let self = self,
                  let dict = result as? [String: Any],
                  let contentWidth = dict["width"] as? CGFloat,
                  let contentHeight = dict["height"] as? CGFloat else {
                self?.cleanup()
                return
            }

            let targetWidth = self.pageSize.width

            // If content is wider than target, scale it down
            if contentWidth > targetWidth {
                let scale = targetWidth / contentWidth
                let scaleJS = """
                (function() {
                    document.body.style.transformOrigin = 'top left';
                    document.body.style.transform = 'scale(\(scale))';
                    document.body.style.width = '\(Int(contentWidth))px';
                    return document.body.scrollHeight * \(scale);
                })()
                """

                wv.evaluateJavaScript(scaleJS) { [weak self] result, _ in
                    guard let self = self else { return }
                    let scaledHeight = (result as? CGFloat) ?? (contentHeight * scale)
                    self.finishMeasureAndCapture(webView: wv, contentHeight: scaledHeight)
                }
            } else {
                self.finishMeasureAndCapture(webView: wv, contentHeight: contentHeight)
            }
        }
    }

    private func finishMeasureAndCapture(webView wv: WKWebView, contentHeight: CGFloat) {
        let pageHeight = self.pageSize.height
        self.expectedPages = max(1, Int(ceil(contentHeight / pageHeight)))

        // Store page count
        if let key = self.baseKey {
            HTMLSnapshotCache.shared.setPageCount(self.expectedPages, for: key)
        }

        // Resize webview to full content height for capturing
        wv.frame = CGRect(x: 0, y: 0, width: self.pageSize.width, height: contentHeight)

        // Start capturing pages
        self.currentPageIndex = 0
        self.capturePage()
    }

    private func capturePage() {
        guard let wv = webView, let key = baseKey else {
            cleanup()
            return
        }

        guard currentPageIndex < expectedPages else {
            // All pages captured - mark complete
            HTMLSnapshotCache.shared.markComplete(baseKey: key)
            if let images = HTMLSnapshotCache.shared.images(for: key) {
                DispatchQueue.main.async {
                    self.pages = images
                    self.isLoading = false
                }
            }
            cleanup()
            return
        }

        let pageHeight = pageSize.height
        let yOffset = CGFloat(currentPageIndex) * pageHeight
        let remainingHeight = wv.frame.height - yOffset
        let captureHeight = min(pageHeight, remainingHeight)

        let config = WKSnapshotConfiguration()
        config.rect = CGRect(x: 0, y: yOffset, width: pageSize.width, height: captureHeight)

        wv.takeSnapshot(with: config) { [weak self] image, error in
            guard let self = self, let image = image else {
                self?.cleanup()
                return
            }

            // Store this page
            let pageKey = "\(key)_p\(self.currentPageIndex)"
            HTMLSnapshotCache.shared.store(image: image, for: pageKey)

            // Move to next page
            self.currentPageIndex += 1
            self.capturePage()
        }
    }

    private func cleanup() {
        if let key = baseKey {
            Self.removePending(key)
        }
        webView?.navigationDelegate = nil
        webView = nil
    }

    deinit {
        if let observer = cacheObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

struct BottomNavView: View {
    let isUnreadOnly: Bool
    let onInboxTap: () -> Void
    let onSearchTap: () -> Void
    let onUnreadToggle: () -> Void
    let onShieldTap: () -> Void

    var body: some View {
        HStack {
            Button(action: onInboxTap) {
                Image(systemName: "tray")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.black)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Button(action: onUnreadToggle) {
                Image(systemName: isUnreadOnly ? "envelope.badge.fill" : "envelope.badge")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(isUnreadOnly ? .black : .gray.opacity(0.5))
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Button(action: onShieldTap) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.gray.opacity(0.5))
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Button(action: onSearchTap) {
                Image(systemName: "magnifyingglass")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.gray.opacity(0.5))
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 28)
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

struct InlineReplyBar: View {
    let senderName: String
    let subject: String
    let recipientEmail: String
    let isSending: Bool
    let onSend: (String) -> Void
    let onCancel: () -> Void

    @State private var replyText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color(white: 0.92))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Replying to \(senderName)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.gray)

                    Spacer()

                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.gray)
                            .frame(width: 24, height: 24)
                    }
                }

                Text(subject)
                    .font(.caption)
                    .foregroundColor(.gray.opacity(0.8))
                    .lineLimit(1)

                HStack(spacing: 10) {
                    TextField(
                        "",
                        text: $replyText,
                        prompt: Text("Add your reply...")
                            .foregroundColor(.gray.opacity(0.8)),
                        axis: .vertical
                    )
                        .font(.subheadline)
                        .foregroundColor(.black)
                        .tint(.black)
                        .lineLimit(1...4)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(white: 0.95))
                        .cornerRadius(20)
                        .focused($isFocused)

                    Button(action: {
                        if !replyText.isEmpty {
                            onSend(replyText)
                        }
                    }) {
                        Image(systemName: isSending ? "arrow.up.circle" : "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(replyText.isEmpty ? .gray.opacity(0.4) : .black)
                    }
                    .disabled(replyText.isEmpty || isSending)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 20)
            .background(Color.white)
        }
        .onAppear {
            isFocused = true
        }
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

struct ForwardComposeView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var contactStore = ContactStore.shared
    let thread: EmailThread
    let isSending: Bool
    let onSend: (String, String, String) -> Void

    @State private var searchText = ""
    @State private var selectedContacts: Set<String> = []  // emails
    @State private var note = ""
    @FocusState private var isSearchFocused: Bool

    private var filteredContacts: [ContactStore.Contact] {
        let sorted = contactStore.contacts.sorted { $0.name.lowercased() < $1.name.lowercased() }
        if searchText.isEmpty {
            return sorted
        }
        let query = searchText.lowercased()
        return sorted.filter {
            $0.name.lowercased().contains(query) || $0.email.contains(query)
        }
    }

    private var isValidEmail: Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return query.contains("@") && query.contains(".")
    }

    private var canSend: Bool {
        !selectedContacts.isEmpty || isValidEmail
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color(white: 0.85))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 12)

            // Header with back button and search
            HStack(spacing: 12) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(width: 32, height: 32)
                        .background(Color(white: 0.95))
                        .clipShape(Circle())
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                        .font(.body)

                    TextField(
                        "",
                        text: $searchText,
                        prompt: Text("Search or enter email")
                            .foregroundColor(.gray.opacity(0.8))
                    )
                        .font(.body)
                        .foregroundColor(.black)
                        .tint(.black)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .focused($isSearchFocused)
                        .onSubmit {
                            if isValidEmail {
                                selectedContacts.insert(searchText.trimmingCharacters(in: .whitespaces).lowercased())
                                searchText = ""
                            }
                        }

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .font(.body)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(white: 0.95))
                .cornerRadius(10)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Rectangle()
                .fill(Color(white: 0.92))
                .frame(height: 1)

            // Selected contacts chips
            if !selectedContacts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(selectedContacts), id: \.self) { email in
                            HStack(spacing: 6) {
                                Text(displayName(for: email))
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.black)
                                Button(action: { selectedContacts.remove(email) }) {
                                    Image(systemName: "xmark")
                                        .font(.caption2.weight(.bold))
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(white: 0.92))
                            .cornerRadius(16)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                Rectangle()
                    .fill(Color(white: 0.92))
                    .frame(height: 1)
            }

            // Contacts list
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Add email option when typing valid email
                    if isValidEmail && !selectedContacts.contains(searchText.lowercased()) {
                        Button(action: {
                            selectedContacts.insert(searchText.trimmingCharacters(in: .whitespaces).lowercased())
                            searchText = ""
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "plus")
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(.gray)
                                    .frame(width: 30, height: 30)
                                    .background(Color(white: 0.95))
                                    .overlay(
                                        Circle()
                                            .stroke(Color(white: 0.9), lineWidth: 1)
                                    )
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Add email")
                                        .font(.subheadline)
                                        .foregroundColor(.black)
                                    Text(searchText)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .padding(.leading, 58)
                    }

                    if !filteredContacts.isEmpty {
                        Text("Suggestions")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)

                        ForEach(filteredContacts) { contact in
                            Button {
                                if selectedContacts.contains(contact.email) {
                                    selectedContacts.remove(contact.email)
                                } else {
                                    selectedContacts.insert(contact.email)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack(alignment: .bottomTrailing) {
                                        AvatarView(initials: contact.initials, isLarge: false)

                                        if selectedContacts.contains(contact.email) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.white, .black)
                                                .offset(x: 2, y: 2)
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(contact.name)
                                            .font(.subheadline)
                                            .foregroundColor(.black)
                                        Text(contact.email)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .padding(.leading, 58)
                        }
                    } else if !isValidEmail {
                        VStack(spacing: 12) {
                            Image(systemName: "at")
                                .font(.system(size: 36))
                                .foregroundColor(.gray.opacity(0.4))
                            Text(searchText.isEmpty ? "No contacts yet" : "No matches")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.gray)
                            if !searchText.isEmpty {
                                Text("Enter a full email address")
                                    .font(.caption)
                                    .foregroundColor(.gray.opacity(0.8))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }
                }
            }

            Spacer(minLength: 0)

            // Message input and send button
            VStack(spacing: 10) {
                Rectangle()
                    .fill(Color(white: 0.92))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Forwarding")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.gray)
                    Text("\(thread.subject) — \(thread.sender.name)")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.8))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                TextField(
                    "",
                    text: $note,
                    prompt: Text("Write a message...")
                        .foregroundColor(.gray.opacity(0.8)),
                    axis: .vertical
                )
                    .font(.body)
                    .foregroundColor(.black)
                    .tint(.black)
                    .lineLimit(1...3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(white: 0.95))
                    .cornerRadius(20)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                Button(action: sendForward) {
                    Text(isSending ? "Sending..." : "Send")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canSend ? Color.black : Color.gray.opacity(0.3))
                        .cornerRadius(24)
                }
                .disabled(!canSend || isSending)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .background(Color.white)
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.white)
        .presentationDragIndicator(.hidden)
    }

    private func displayName(for email: String) -> String {
        if let contact = contactStore.contacts.first(where: { $0.email == email }) {
            return contact.name
        }
        return email
    }

    private func sendForward() {
        var allRecipients = selectedContacts
        if isValidEmail {
            allRecipients.insert(searchText.trimmingCharacters(in: .whitespaces).lowercased())
        }
        let recipients = allRecipients.joined(separator: ", ")
        let subject = "Fwd: \(thread.subject)"
        var body = ""
        if !note.isEmpty {
            body += "\(note)\n\n"
        }
        body += "---------- Forwarded message ----------\n"
        body += "From: \(thread.sender.name)\n"
        body += "Subject: \(thread.subject)\n\n"
        body += thread.pages.joined(separator: "\n")
        onSend(recipients, subject, body)
        dismiss()
    }
}

struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var gmailViewModel: GmailViewModel
    @State private var description = ""
    @State private var screenshot: UIImage?
    @State private var isSending = false
    @State private var formViewForCapture: UIView?

    var body: some View {
        NavigationStack {
            FeedbackFormContent(
                description: $description,
                screenshot: $screenshot,
                onCapture: captureScreenshot,
                onViewReady: { view in formViewForCapture = view }
            )
            .navigationTitle("Report Bug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSending ? "Sending..." : "Send") { sendFeedback() }
                        .disabled(description.isEmpty || isSending)
                }
            }
        }
    }

    private func captureScreenshot() {
        guard let view = formViewForCapture else { return }
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        screenshot = renderer.image { ctx in
            view.layer.render(in: ctx.cgContext)
        }
    }

    private func sendFeedback() {
        isSending = true
        Task {
            await gmailViewModel.sendEmail(
                to: "simba161921@gmail.com",
                subject: "[Bug Report] User Feedback",
                body: description
            )
            isSending = false
            dismiss()
        }
    }
}

private struct FeedbackFormContent: View {
    @Binding var description: String
    @Binding var screenshot: UIImage?
    let onCapture: () -> Void
    let onViewReady: (UIView) -> Void

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading) {
                Text("Describe the issue")
                    .font(.caption)
                    .foregroundColor(.gray)
                TextEditor(text: $description)
                    .frame(height: 120)
                    .padding(8)
                    .background(Color(white: 0.97))
                    .cornerRadius(8)
            }

            HStack {
                Text("Screenshot (optional)")
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                Button("Capture") { onCapture() }
                    .font(.caption.weight(.medium))
            }

            if let img = screenshot {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 150)
                    .cornerRadius(8)
            }

            Spacer()
        }
        .padding()
        .background(
            ViewCaptureHelper(onViewReady: onViewReady)
        )
    }
}

private struct ViewCaptureHelper: UIViewRepresentable {
    let onViewReady: (UIView) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        DispatchQueue.main.async {
            if let parentView = view.superview?.superview {
                onViewReady(parentView)
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
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
            // Render full HTML as a single page (no chunking)
            pages.append(CardPage(kind: .html(html)))
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
            Text("Sign in to show your real inbox.")
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
