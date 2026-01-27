import SwiftUI

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var gmailViewModel: GmailViewModel
    @State private var searchText = ""
    @State private var detailThread: EmailThread?
    @FocusState private var isFocused: Bool

    var onOpenThread: ((EmailThread) -> Void)?
    var onReply: ((EmailThread) -> Void)?
    var onForward: ((EmailThread) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: {
                    gmailViewModel.clearSearchResults()
                    dismiss()
                }) {
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
                        prompt: Text("Search emails...")
                            .foregroundColor(.gray.opacity(0.8))
                    )
                        .focused($isFocused)
                        .foregroundColor(.black)
                        .tint(.black)
                        .submitLabel(.search)
                        .onSubmit {
                            Task { await gmailViewModel.search(query: searchText) }
                        }

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            gmailViewModel.clearSearchResults()
                        }) {
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
            .padding(.vertical, 12)
            .background(Color.white)

            Rectangle()
                .fill(Color(white: 0.92))
                .frame(height: 1)

            if gmailViewModel.isSearching {
                VStack {
                    Spacer()
                    ProgressView("Searching...")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if gmailViewModel.searchResults.isEmpty && !searchText.isEmpty {
                let suggestions = ContactStore.shared.suggestions(for: searchText)
                if !suggestions.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Suggestions")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.gray)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)

                            ForEach(suggestions) { contact in
                                Button {
                                    searchText = "from:\(contact.email)"
                                    Task { await gmailViewModel.search(query: searchText) }
                                } label: {
                                    HStack(spacing: 12) {
                                        AvatarView(initials: contact.initials, isLarge: false)
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
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.gray.opacity(0.5))
                        Text("No results found")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("Try a different search term")
                            .font(.subheadline)
                            .foregroundColor(.gray.opacity(0.8))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            } else if gmailViewModel.searchResults.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.gray.opacity(0.5))
                    Text("Search your emails")
                        .font(.headline)
                        .foregroundColor(.gray)
                    Text("Enter a keyword to find messages")
                        .font(.subheadline)
                        .foregroundColor(.gray.opacity(0.8))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(gmailViewModel.searchResults) { thread in
                            EmailCardView(
                                thread: thread,
                                isDetailView: false,
                                isRoot: true,
                                depth: 0,
                                renderHTML: true,
                                onThreadTap: { onOpenThread?(thread) },
                                onCardTap: { detailThread = thread },
                                onReply: { onReply?(thread) },
                                onForward: { onForward?(thread) },
                                onDelete: {
                                    if let threadID = thread.threadID {
                                        Task { await gmailViewModel.trashThread(threadID: threadID) }
                                    }
                                },
                                onSave: nil,
                                onCardAppear: nil
                            )
                        }
                    }
                }
            }
        }
        .background(Color.white)
        .onAppear {
            isFocused = true
        }
        .onDisappear {
            gmailViewModel.clearSearchResults()
        }
        .fullScreenCover(item: $detailThread) { thread in
            EmailDetailView(
                thread: thread,
                onOpenThread: { onOpenThread?(thread) },
                onReply: { onReply?(thread) },
                onForward: { onForward?(thread) }
            )
            .environmentObject(gmailViewModel)
        }
    }
}

#Preview {
    SearchView()
        .environmentObject(GmailViewModel())
}
