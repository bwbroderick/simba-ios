import SwiftUI
import UIKit

struct InboxView: View {
    @State private var path: [UUID] = []
    @StateObject private var gmailViewModel = GmailViewModel()
    @State private var showCompose = false
    @State private var showUnreadOnly = false
    @State private var replyingToThread: EmailThread?
    @State private var forwardingThread: EmailThread?
    @State private var detailThread: EmailThread?
    @State private var detailScrollFraction: Double = 0.0
    @State private var showFeedback = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var showSearch = false
    @State private var showSideDrawer = false
    @State private var scrollToTopTrigger = false
    @State private var attachmentToPreview: EmailAttachment?
    @State private var attachmentData: Data?
    @State private var isDownloadingAttachment = false

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            HeaderView(
                            title: gmailViewModel.currentLabel.displayName,
                            showsBack: false,
                            onBack: nil,
                            onMeTap: { showSideDrawer = true }
                        )
                        .id("feed-top")

                        if !gmailViewModel.isSignedIn {
                            GmailConnectCard(onConnect: gmailViewModel.signIn)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }

                        if gmailViewModel.isLoading {
                            ProgressView("Loading…")
                                .padding(.vertical, 16)
                        }

                        if let errorMessage = gmailViewModel.errorMessage, !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal, 16)
                        }

                        let activeThreads = gmailViewModel.threads

                        ForEach(activeThreads) { thread in
                            EmailCardView(
                                thread: thread,
                                isDetailView: false,
                                isRoot: true,
                                depth: 0,
                                renderHTML: true,
                                onThreadTap: {
                                    path.append(thread.id)
                                },
                                onCardTap: { scrollFraction in
                                    detailScrollFraction = scrollFraction
                                    detailThread = thread
                                },
                                onReply: {
                                    replyingToThread = thread
                                },
                                onForward: {
                                    forwardingThread = thread
                                },
                                onDelete: {
                                    if let threadID = thread.threadID {
                                        Task { await gmailViewModel.trashThread(threadID: threadID) }
                                    }
                                },
                                onCardAppear: {
                                    if thread.isUnread, let threadID = thread.threadID {
                                        gmailViewModel.queueMarkRead(threadID: threadID)
                                    }
                                },
                                onStar: {
                                    if let threadID = thread.threadID {
                                        Task { await gmailViewModel.toggleStar(threadID: threadID, isCurrentlyStarred: thread.isStarred) }
                                    }
                                },
                                onArchive: {
                                    if let threadID = thread.threadID {
                                        Task { await gmailViewModel.archiveThread(threadID: threadID) }
                                    }
                                },
                                onAttachmentTap: { attachment in
                                    attachmentToPreview = attachment
                                    downloadAndPreviewAttachment(attachment)
                                }
                            )
                        }

                        // Pagination sentinel
                        if gmailViewModel.hasMorePages {
                            ProgressView()
                                .padding(.vertical, 16)
                                .onAppear {
                                    Task { await gmailViewModel.loadMoreThreads() }
                                }
                        }

                        if gmailViewModel.isSignedIn, !gmailViewModel.isLoading, activeThreads.isEmpty {
                            EmptyStateView(
                                title: showUnreadOnly ? "No unread email" : "\(gmailViewModel.currentLabel.displayName) empty",
                                message: showUnreadOnly
                                    ? "You're all caught up."
                                    : "Pull to refresh or wait for new mail."
                            )
                            .padding(.vertical, 32)
                        }
                    }
                    }
                    .padding(.bottom, 120)
                    .background(Color.white)
                    .refreshable {
                        await gmailViewModel.fetchInbox(unreadOnly: showUnreadOnly)
                    }
                    .onChange(of: scrollToTopTrigger) {
                        withAnimation {
                            scrollProxy.scrollTo("feed-top", anchor: .top)
                        }
                    }
                }
                .navigationDestination(for: UUID.self) { threadID in
                    let activeThreads = gmailViewModel.threads
                    if let thread = activeThreads.first(where: { $0.id == threadID }) {
                        ThreadView(thread: thread)
                            .environmentObject(gmailViewModel)
                    }
                }

                VStack(spacing: 0) {
                    if let thread = replyingToThread {
                        InlineReplyBar(
                            senderName: thread.sender.name,
                            subject: thread.subject,
                            recipientEmail: thread.sender.email ?? "",
                            isSending: gmailViewModel.isSending,
                            onSend: { replyText in
                                let to = thread.sender.email ?? ""
                                let subject = thread.subject.hasPrefix("Re:") ? thread.subject : "Re: \(thread.subject)"
                                Task {
                                    await gmailViewModel.sendEmail(to: to, subject: subject, body: replyText)
                                    replyingToThread = nil
                                }
                            },
                            onCancel: {
                                replyingToThread = nil
                            }
                        )
                        .padding(.bottom, keyboardHeight > 0 ? keyboardHeight : 0)
                    } else {
                        BottomNavView(
                            isUnreadOnly: showUnreadOnly,
                            onInboxTap: {
                                scrollToTopTrigger.toggle()
                            },
                            onSearchTap: {
                                showSearch = true
                            },
                            onUnreadToggle: {
                                showUnreadOnly.toggle()
                                Task { await gmailViewModel.fetchInbox(unreadOnly: showUnreadOnly) }
                            },
                            labelName: gmailViewModel.currentLabel.displayName
                        )
                    }
                }
                .background(Color.white.ignoresSafeArea(edges: .bottom))

                if replyingToThread == nil {
                    FloatingComposeButton {
                        showCompose = true
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 20)
                    .padding(.bottom, 98)
                }
            }
            .overlay {
                if showSideDrawer {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showSideDrawer = false
                        }
                }
            }
            .overlay(alignment: .leading) {
                SideDrawerView(
                    isPresented: $showSideDrawer,
                    onSignOut: {
                        gmailViewModel.signOut()
                        showSideDrawer = false
                    },
                    onBugReport: {
                        showSideDrawer = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showFeedback = true
                        }
                    },
                    labels: gmailViewModel.labels,
                    currentLabel: gmailViewModel.currentLabel,
                    onLabelTap: { label in
                        Task { await gmailViewModel.switchLabel(label) }
                    }
                )
                .frame(width: 280)
                .offset(x: showSideDrawer ? 0 : -320)
                .allowsHitTesting(showSideDrawer)
            }
            .animation(.easeOut(duration: 0.25), value: showSideDrawer)
            .ignoresSafeArea(edges: .bottom)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    withAnimation(.easeOut(duration: 0.25)) {
                        keyboardHeight = frame.height
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    keyboardHeight = 0
                }
            }
            .task {
                gmailViewModel.restoreSession()
            }
            .sheet(isPresented: $showCompose) {
                ComposeView(
                    isSending: gmailViewModel.isSending,
                    onSend: { to, subject, body, cc, bcc in
                        Task { await gmailViewModel.sendEmail(to: to, subject: subject, body: body, cc: cc, bcc: bcc) }
                    },
                    onSaveDraft: { to, subject, body, cc, bcc in
                        Task { _ = await gmailViewModel.createDraft(to: to, subject: subject, body: body, cc: cc, bcc: bcc) }
                    }
                )
            }
            .sheet(item: $forwardingThread) { thread in
                ForwardComposeView(
                    thread: thread,
                    isSending: gmailViewModel.isSending,
                    onSend: { to, subject, body in
                        Task {
                            await gmailViewModel.sendEmail(to: to, subject: subject, body: body)
                            forwardingThread = nil
                        }
                    }
                )
            }
            .sheet(isPresented: $showFeedback) {
                FeedbackView()
                    .environmentObject(gmailViewModel)
            }
            .fullScreenCover(isPresented: $showSearch) {
                SearchView(
                    onOpenThread: { thread in
                        showSearch = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            path.append(thread.id)
                        }
                    },
                    onReply: { thread in
                        showSearch = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            replyingToThread = thread
                        }
                    },
                    onForward: { thread in
                        showSearch = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            forwardingThread = thread
                        }
                    }
                )
                .environmentObject(gmailViewModel)
            }
            .fullScreenCover(item: $detailThread) { thread in
                EmailDetailView(
                    thread: thread,
                    initialScrollFraction: detailScrollFraction,
                    onOpenThread: {
                        path.append(thread.id)
                    },
                    onReply: {
                        replyingToThread = thread
                    },
                    onForward: {
                        forwardingThread = thread
                    }
                )
                .environmentObject(gmailViewModel)
            }
            .sheet(item: $attachmentToPreview) { attachment in
                AttachmentPreviewSheet(
                    attachment: attachment,
                    data: attachmentData,
                    isDownloading: isDownloadingAttachment
                )
            }
        }
    }

    private func downloadAndPreviewAttachment(_ attachment: EmailAttachment) {
        isDownloadingAttachment = true
        attachmentData = nil
        Task {
            let data = await gmailViewModel.downloadAttachment(
                messageId: attachment.messageId,
                attachmentId: attachment.attachmentId
            )
            attachmentData = data
            isDownloadingAttachment = false
        }
    }
}

struct AttachmentPreviewSheet: View {
    let attachment: EmailAttachment
    let data: Data?
    let isDownloading: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                if isDownloading {
                    Spacer()
                    ProgressView("Downloading…")
                    Spacer()
                } else if let data {
                    if attachment.mimeType.hasPrefix("image/"), let image = UIImage(data: data) {
                        ScrollView {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding()
                        }
                    } else {
                        VStack(spacing: 16) {
                            Spacer()
                            Image(systemName: attachment.iconName)
                                .font(.system(size: 48))
                                .foregroundColor(.gray)
                            Text(attachment.filename)
                                .font(.headline)
                            Text(attachment.formattedSize)
                                .font(.subheadline)
                                .foregroundColor(.gray)

                            ShareLink(item: AttachmentDataItem(data: data, filename: attachment.filename)) {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Share")
                                }
                                .font(.body.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 24)
                                .background(Color.black)
                                .cornerRadius(20)
                            }
                            Spacer()
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36))
                            .foregroundColor(.gray)
                        Text("Failed to download")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Spacer()
                    }
                }
            }
            .navigationTitle(attachment.filename)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct AttachmentDataItem: Transferable {
    let data: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .data) { item in
            item.data
        }
    }
}

#Preview {
    InboxView()
}
