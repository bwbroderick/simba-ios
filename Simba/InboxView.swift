import SwiftUI

struct InboxView: View {
    @State private var path: [UUID] = []
    @StateObject private var gmailViewModel = GmailViewModel()
    @State private var showCompose = false
    @State private var showUnreadOnly = false

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottomTrailing) {
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
                                    path.append(thread.id)
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

                BottomNavView(isUnreadOnly: showUnreadOnly) {
                    showUnreadOnly.toggle()
                    Task { await gmailViewModel.fetchInbox(unreadOnly: showUnreadOnly) }
                }
                FloatingComposeButton {
                    showCompose = true
                }
                .padding(.trailing, 20)
                .padding(.bottom, 98)
            }
            .ignoresSafeArea(edges: .bottom)
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
        }
    }
}

#Preview {
    InboxView()
}
