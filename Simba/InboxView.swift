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

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            HeaderView(
                            title: "Inbox",
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
                            }
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
                    onSend: { to, subject, body in
                        Task { await gmailViewModel.sendEmail(to: to, subject: subject, body: body) }
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
        }
    }
}

#Preview {
    InboxView()
}
