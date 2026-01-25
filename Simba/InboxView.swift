import SwiftUI
import UIKit

struct InboxView: View {
    @State private var path: [UUID] = []
    @StateObject private var gmailViewModel = GmailViewModel()
    @State private var showCompose = false
    @State private var showUnreadOnly = false
    @State private var replyingToThread: EmailThread?
    @State private var keyboardHeight: CGFloat = 0
    @State private var showSearch = false

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        HeaderView(title: "Inbox", showsBack: false, onBack: nil)

                        if !gmailViewModel.isSignedIn {
                            GmailConnectCard(onConnect: gmailViewModel.signIn)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }

                        if gmailViewModel.isLoading {
                            ProgressView("Loading Gmail…")
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
                                onReply: {
                                    replyingToThread = thread
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
                                }
                            )
                        }

                        if gmailViewModel.isSignedIn, !gmailViewModel.isLoading, activeThreads.isEmpty {
                            EmptyStateView(
                                title: showUnreadOnly ? "No unread email" : "Inbox empty",
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
                        .padding(.bottom, keyboardHeight > 0 ? keyboardHeight - 34 : 0)
                    } else {
                        BottomNavView(isUnreadOnly: showUnreadOnly, onSearchTap: {
                            showSearch = true
                        }) {
                            showUnreadOnly.toggle()
                            Task { await gmailViewModel.fetchInbox(unreadOnly: showUnreadOnly) }
                        }
                    }
                }

                if replyingToThread == nil {
                    FloatingComposeButton {
                        showCompose = true
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 20)
                    .padding(.bottom, 98)
                }
            }
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
                    onSend: { to, subject, body in
                        Task { await gmailViewModel.sendEmail(to: to, subject: subject, body: body) }
                    }
                )
            }
            .sheet(isPresented: $showSearch) {
                SearchView()
                    .environmentObject(gmailViewModel)
            }
        }
    }
}

#Preview {
    InboxView()
}
