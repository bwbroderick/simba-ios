import SwiftUI

struct EmailDetailView: View {
    let thread: EmailThread
    var initialScrollFraction: Double = 0.0
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var gmailViewModel: GmailViewModel

    var onOpenThread: (() -> Void)?
    var onReply: (() -> Void)?
    var onForward: (() -> Void)?

    @State private var showReplyCompose = false
    @State private var attachmentToPreview: EmailAttachment?
    @State private var attachmentData: Data?
    @State private var isDownloadingAttachment = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(width: 32, height: 32)
                            .background(Color(white: 0.95))
                            .clipShape(Circle())
                    }

                    AvatarView(initials: thread.sender.initials, isLarge: true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(thread.sender.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.black)

                        if let email = thread.sender.email {
                            Text(email)
                                .font(.caption)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Text(thread.timestamp.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.gray.opacity(0.7))
                        .tracking(0.8)

                    // Star button
                    Button(action: {
                        if let threadID = thread.threadID {
                            Task { await gmailViewModel.toggleStar(threadID: threadID, isCurrentlyStarred: thread.isStarred) }
                        }
                    }) {
                        Image(systemName: thread.isStarred ? "star.fill" : "star")
                            .font(.body)
                            .foregroundColor(thread.isStarred ? .orange : .gray.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white)

                // Subject bar
                VStack(alignment: .leading, spacing: 4) {
                    Text(thread.subject)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.black)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(white: 0.98))
                .overlay(
                    Rectangle()
                        .fill(Color(white: 0.92))
                        .frame(height: 1),
                    alignment: .bottom
                )

                // Attachments bar
                if !thread.attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(thread.attachments) { attachment in
                                Button(action: {
                                    attachmentToPreview = attachment
                                    downloadAndPreview(attachment)
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: attachment.iconName)
                                            .font(.caption2.weight(.medium))
                                            .foregroundColor(.gray)
                                        Text(attachment.filename)
                                            .font(.caption2.weight(.medium))
                                            .foregroundColor(.black.opacity(0.8))
                                            .lineLimit(1)
                                        Text(attachment.formattedSize)
                                            .font(.caption2)
                                            .foregroundColor(.gray.opacity(0.7))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(white: 0.95))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .background(Color(white: 0.98))
                }

                // HTML Content
                if let html = thread.htmlBody, !html.isEmpty {
                    InteractiveHTMLView(
                        html: html,
                        initialScrollFraction: initialScrollFraction
                    ) { url in
                        UIApplication.shared.open(url)
                    }
                } else {
                    // Fallback for plain text
                    ScrollView {
                        Text(thread.pages.joined(separator: "\n\n"))
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                    .background(Color(white: 0.97))
                }

                // Action bar
                ActionBar(
                    hasThread: thread.messageCount > 1,
                    messageCount: thread.messageCount,
                    onReply: {
                        if let onReply = onReply {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onReply()
                            }
                        } else {
                            showReplyCompose = true
                        }
                    },
                    onArchive: {
                        if let threadID = thread.threadID {
                            Task {
                                await gmailViewModel.archiveThread(threadID: threadID)
                                dismiss()
                            }
                        }
                    },
                    onForward: {
                        if let onForward = onForward {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onForward()
                            }
                        }
                    },
                    onDelete: {
                        if let threadID = thread.threadID {
                            Task {
                                await gmailViewModel.trashThread(threadID: threadID)
                                dismiss()
                            }
                        }
                    },
                    onThread: {
                        if let onOpenThread = onOpenThread {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onOpenThread()
                            }
                        }
                    }
                )
            }
            .background(Color.white)
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showReplyCompose) {
            ReplyComposeView(
                to: thread.sender.email ?? "",
                subject: thread.subject.hasPrefix("Re:") ? thread.subject : "Re: \(thread.subject)",
                isSending: gmailViewModel.isSending,
                onSend: { to, subject, body, cc, bcc in
                    Task { await gmailViewModel.sendEmail(to: to, subject: subject, body: body, cc: cc, bcc: bcc) }
                }
            )
        }
        .sheet(item: $attachmentToPreview) { attachment in
            AttachmentPreviewSheet(
                attachment: attachment,
                data: attachmentData,
                isDownloading: isDownloadingAttachment
            )
        }
    }

    private func downloadAndPreview(_ attachment: EmailAttachment) {
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

private struct ActionBar: View {
    let hasThread: Bool
    let messageCount: Int
    let onReply: () -> Void
    let onArchive: () -> Void
    let onForward: () -> Void
    let onDelete: () -> Void
    let onThread: () -> Void

    var body: some View {
        HStack {
            Button(action: onReply) {
                VStack(spacing: 4) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.title3.weight(.medium))
                    Text("Reply")
                        .font(.caption2)
                }
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity)
            }

            Button(action: onArchive) {
                VStack(spacing: 4) {
                    Image(systemName: "archivebox")
                        .font(.title3.weight(.medium))
                    Text("Archive")
                        .font(.caption2)
                }
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity)
            }

            Button(action: onForward) {
                VStack(spacing: 4) {
                    Image(systemName: "arrowshape.turn.up.right")
                        .font(.title3.weight(.medium))
                    Text("Forward")
                        .font(.caption2)
                }
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity)
            }

            Button(action: onDelete) {
                VStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.title3.weight(.medium))
                    Text("Delete")
                        .font(.caption2)
                }
                .foregroundColor(.red.opacity(0.8))
                .frame(maxWidth: .infinity)
            }

            Button(action: onThread) {
                VStack(spacing: 4) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bubble.left")
                            .font(.title3.weight(.medium))

                        Text("\(messageCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(3)
                            .background(hasThread ? Color.blue : Color.gray.opacity(0.4))
                            .clipShape(Circle())
                            .offset(x: 8, y: -4)
                    }
                    Text("Thread")
                        .font(.caption2)
                }
                .foregroundColor(hasThread ? .gray : .gray.opacity(0.3))
                .frame(maxWidth: .infinity)
            }
            .disabled(!hasThread)
        }
        .padding(.vertical, 12)
        .padding(.bottom, 20)
        .background(Color.white)
        .overlay(
            Rectangle()
                .fill(Color(white: 0.92))
                .frame(height: 1),
            alignment: .top
        )
    }
}

#Preview {
    EmailDetailView(thread: SampleData.threads.first!)
        .environmentObject(GmailViewModel())
}
