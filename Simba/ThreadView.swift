import SwiftUI

struct ThreadView: View {
    let thread: EmailThread
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var gmailViewModel: GmailViewModel
    @StateObject private var loader = GmailThreadLoader()
    @State private var showInlineReply = false
    @State private var detailMessage: EmailThread?
    @State private var keyboardHeight: CGFloat = 0
    @State private var detailScrollFraction: Double = 0.0

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    HeaderView(title: "Thread", showsBack: true, onBack: { dismiss() })

                    let messages = loader.messages.isEmpty ? thread.messages : loader.messages

                    if loader.isLoading {
                        ProgressView("Loading thread…")
                            .foregroundColor(.gray)
                            .tint(.gray)
                            .padding(.vertical, 16)
                    }

                    if let errorMessage = loader.errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal, 16)
                    }

                    ForEach(messages) { message in
                        let messageThread = EmailThread(
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
                        )
                        EmailCardView(
                            thread: messageThread,
                            isDetailView: true,
                            isRoot: message.isRoot,
                            depth: message.depth,
                            renderHTML: true,
                            onThreadTap: nil,
                            onCardTap: { scrollFraction in
                                detailScrollFraction = scrollFraction
                                detailMessage = messageThread
                            },
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

            if showInlineReply {
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
                            showInlineReply = false
                        }
                    },
                    onCancel: {
                        showInlineReply = false
                    }
                )
                .padding(.bottom, keyboardHeight > 0 ? keyboardHeight : 0)
            } else {
                ReplyBarView(name: thread.sender.name) {
                    showInlineReply = true
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationBarBackButtonHidden(true)
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
            if let threadID = thread.threadID {
                if loader.messages.isEmpty {
                    await loader.load(threadID: threadID)
                }
                if thread.isUnread {
                    gmailViewModel.queueMarkRead(threadID: threadID)
                }
            }
        }
        .fullScreenCover(item: $detailMessage) { messageThread in
            EmailDetailView(
                thread: messageThread,
                initialScrollFraction: detailScrollFraction
            )
            .environmentObject(gmailViewModel)
        }
    }
}

#Preview {
    ThreadView(thread: SampleData.threads.first!)
}
