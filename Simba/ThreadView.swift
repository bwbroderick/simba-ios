import SwiftUI

struct ThreadView: View {
    let thread: EmailThread
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var gmailViewModel: GmailViewModel
    @StateObject private var loader = GmailThreadLoader()
    @State private var showReplyCompose = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    HeaderView(title: "Thread", showsBack: true, onBack: { dismiss() })

                    let messages = loader.messages.isEmpty ? thread.messages : loader.messages

                    if loader.isLoading {
                        ProgressView("Loading thread…")
                            .padding(.vertical, 16)
                    }

                    if let errorMessage = loader.errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal, 16)
                    }

                    ForEach(messages) { message in
                        EmailCardView(
                            thread: EmailThread(
                                threadID: nil,
                                sender: message.sender,
                                subject: message.subject,
                                pages: message.pages,
                                htmlBody: message.htmlBody,
                                isUnread: false,
                                messageCount: 0,
                                timestamp: message.timestamp,
                                messages: [],
                                debugVisibility: nil
                            ),
                            isDetailView: true,
                            isRoot: message.isRoot,
                            depth: message.depth,
                            renderHTML: true,
                            onThreadTap: nil,
                            onDelete: {
                                if let threadID = thread.threadID {
                                    Task {
                                        await gmailViewModel.trashThread(threadID: threadID)
                                        dismiss()
                                    }
                                }
                            }
                        )
                    }
                }
            }
            .padding(.bottom, 96)
            .background(Color.white)

            ReplyBarView(name: thread.sender.name) {
                showReplyCompose = true
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationBarBackButtonHidden(true)
        .task {
            if let threadID = thread.threadID {
                if loader.messages.isEmpty {
                    await loader.load(threadID: threadID)
                }
                if thread.isUnread {
                    gmailViewModel.queueMarkRead(threadID: threadID)
                }
            }
        }
        .sheet(isPresented: $showReplyCompose) {
            ReplyComposeView(
                to: thread.sender.email ?? "",
                subject: thread.subject.hasPrefix("Re:") ? thread.subject : "Re: \(thread.subject)",
                isSending: gmailViewModel.isSending,
                onSend: { to, subject, body in
                    Task { await gmailViewModel.sendEmail(to: to, subject: subject, body: body) }
                }
            )
        }
    }
}

#Preview {
    ThreadView(thread: SampleData.threads.first!)
}
