import SwiftUI

struct MailFirewallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = MailFirewallViewModel()
    @ObservedObject private var service = MailFirewallService.shared
    @State private var selectedSection: Section = .dashboard
    @State private var showAddAllowlist = false
    @State private var newPattern = ""
    @State private var newNote = ""

    enum Section: String, CaseIterable {
        case dashboard = "Dashboard"
        case review = "Review"
        case blocked = "Blocked"
        case pending = "Pending"
        case allowlist = "Allowlist"
    }

    var body: some View {
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

                Text("Mail Firewall")
                    .font(.title3.weight(.bold))

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.98))

            // Section picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Section.allCases, id: \.self) { section in
                        Button(action: { selectedSection = section }) {
                            Text(section.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(selectedSection == section ? .white : .black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(selectedSection == section ? Color.black : Color(white: 0.95))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            Rectangle()
                .fill(Color(white: 0.92))
                .frame(height: 1)

            // Error message
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            // Content
            ScrollView {
                switch selectedSection {
                case .dashboard:
                    DashboardSection(stats: viewModel.stats, isLoading: viewModel.isLoading)
                case .review:
                    ReviewSection(emails: viewModel.reviewEmails, isLoading: viewModel.isLoading, viewModel: viewModel)
                case .blocked:
                    BlockedSection(entries: viewModel.blockedEntries, isLoading: viewModel.isLoading, viewModel: viewModel)
                case .pending:
                    PendingSection(unsubs: viewModel.pendingUnsubs, isLoading: viewModel.isLoading, viewModel: viewModel)
                case .allowlist:
                    AllowlistSection(
                        entries: viewModel.allowlist,
                        isLoading: viewModel.isLoading,
                        viewModel: viewModel,
                        onAdd: { showAddAllowlist = true }
                    )
                }
            }
            .refreshable {
                await refreshCurrentSection()
            }
        }
        .background(Color.white)
        .task {
            await viewModel.loadDashboard()
        }
        .onChange(of: selectedSection) { _, section in
            Task { await loadSection(section) }
        }
        .onChange(of: service.isAuthenticated) { _, isAuth in
            if isAuth {
                Task { await loadSection(selectedSection) }
            }
        }
        .sheet(isPresented: $service.showAuthWebView) {
            CloudflareAuthView { jwt in
                service.setToken(jwt)
                service.showAuthWebView = false
            }
        }
        .alert("Add Allowlist Entry", isPresented: $showAddAllowlist) {
            TextField("Pattern (e.g. *@example.com)", text: $newPattern)
            TextField("Note (optional)", text: $newNote)
            Button("Cancel", role: .cancel) {
                newPattern = ""
                newNote = ""
            }
            Button("Add") {
                let pattern = newPattern
                let note = newNote.isEmpty ? nil : newNote
                newPattern = ""
                newNote = ""
                Task { await viewModel.addAllowlistEntry(pattern: pattern, note: note) }
            }
        }
    }

    private func loadSection(_ section: Section) async {
        switch section {
        case .dashboard:
            await viewModel.loadDashboard()
        case .review:
            await viewModel.loadReview()
        case .blocked:
            await viewModel.loadBlocked()
        case .pending:
            await viewModel.loadPending()
        case .allowlist:
            await viewModel.loadAllowlist()
        }
    }

    private func refreshCurrentSection() async {
        await loadSection(selectedSection)
    }
}

// MARK: - Dashboard

private struct DashboardSection: View {
    let stats: FirewallStats?
    let isLoading: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        if isLoading && stats == nil {
            ProgressView()
                .padding(.top, 40)
        } else if let stats {
            LazyVGrid(columns: columns, spacing: 12) {
                StatCard(value: stats.blockedTotal, label: "Blocked", color: .red)
                StatCard(value: stats.reviewCount, label: "Pending Review", color: .orange)
                StatCard(value: stats.pendingUnsubscribes, label: "Pending Unsubs", color: .yellow)
                StatCard(value: stats.allowlistCount, label: "Allowlisted", color: .green)
                StatCard(value: stats.llmSpam, label: "LLM Spam", color: .red)
                StatCard(value: stats.llmNotSpam, label: "LLM Not Spam", color: .green)
                StatCard(value: stats.totalUnsubscribed, label: "Unsubscribed", color: .blue)
                StatCard(value: stats.blockedToday, label: "Blocked Today", color: .orange)
            }
            .padding(16)
        } else {
            Text("No stats available")
                .font(.subheadline)
                .foregroundColor(.gray)
                .padding(.top, 40)
        }
    }
}

private struct StatCard: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text("\(value)")
                .font(.title.weight(.bold))
                .foregroundColor(.black)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(white: 0.97))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Review

private struct ReviewSection: View {
    let emails: [FirewallEmail]
    let isLoading: Bool
    let viewModel: MailFirewallViewModel

    var body: some View {
        if isLoading && emails.isEmpty {
            ProgressView()
                .padding(.top, 40)
        } else if emails.isEmpty {
            EmptyStateView(title: "No emails to review", message: "The review queue is empty.")
                .padding(.top, 32)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(emails) { email in
                    ReviewRow(email: email, viewModel: viewModel)
                }
            }
        }
    }
}

private struct ReviewRow: View {
    let email: FirewallEmail
    let viewModel: MailFirewallViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(initials: initials(for: email.sender ?? ""), isLarge: false)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(email.sender ?? email.sender_email ?? "Unknown")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.black)
                            .lineLimit(1)

                        Spacer()

                        Text((email.received_at ?? "").prefix(10))
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }

                    Text(email.subject ?? "(No subject)")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.black)
                        .lineLimit(2)

                    Text(email.snippet ?? "")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 8) {
                Button(action: { Task { await viewModel.approveEmail(email) } }) {
                    Text("Approve")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green)
                        .clipShape(Capsule())
                }

                Button(action: { Task { await viewModel.approveOnce(email) } }) {
                    Text("Once")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(white: 0.92))
                        .clipShape(Capsule())
                }

                Button(action: { Task { await viewModel.rejectEmail(email) } }) {
                    Text("Reject")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .overlay(
            Rectangle()
                .fill(Color(white: 0.95))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

// MARK: - Blocked

private struct BlockedSection: View {
    let entries: [BlockedEntry]
    let isLoading: Bool
    let viewModel: MailFirewallViewModel

    var body: some View {
        if isLoading && entries.isEmpty {
            ProgressView()
                .padding(.top, 40)
        } else if entries.isEmpty {
            EmptyStateView(title: "No blocked senders", message: "Nothing has been blocked yet.")
                .padding(.top, 32)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    BlockedRow(entry: entry)
                        .swipeActions(edge: .trailing) {
                            Button("Unblock") {
                                Task { await viewModel.unblock(entry) }
                            }
                            .tint(.green)
                        }
                }
            }
        }
    }
}

private struct BlockedRow: View {
    let entry: BlockedEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.displayEmail)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.black)
                    .lineLimit(1)

                Spacer()

                Text(entry.reason ?? "blocked")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.red.opacity(0.8))
                    .clipShape(Capsule())
            }

            if let subject = entry.subject {
                Text(subject)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }

            if let blockedAt = entry.blocked_at {
                Text(blockedAt.prefix(10))
                    .font(.caption2)
                    .foregroundColor(.gray.opacity(0.7))
            }
        }
        .padding(16)
        .background(Color.white)
        .overlay(
            Rectangle()
                .fill(Color(white: 0.95))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

// MARK: - Pending

private struct PendingSection: View {
    let unsubs: [PendingUnsubscribe]
    let isLoading: Bool
    let viewModel: MailFirewallViewModel

    var body: some View {
        if isLoading && unsubs.isEmpty {
            ProgressView()
                .padding(.top, 40)
        } else if unsubs.isEmpty {
            EmptyStateView(title: "No pending unsubscribes", message: "Nothing pending right now.")
                .padding(.top, 32)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(unsubs) { unsub in
                    PendingRow(unsub: unsub, viewModel: viewModel)
                }
            }
        }
    }
}

private struct PendingRow: View {
    let unsub: PendingUnsubscribe
    let viewModel: MailFirewallViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(unsub.sender ?? "Unknown")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.black)
                    .lineLimit(1)

                Spacer()

                Text("\(Int(unsub.daysRemaining))d left")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(unsub.daysRemaining < 1 ? Color.red : Color.orange)
                    .clipShape(Capsule())
            }

            Text(unsub.subject ?? "")
                .font(.caption2)
                .foregroundColor(.gray)
                .lineLimit(1)

            HStack(spacing: 8) {
                if unsub.has_url == true {
                    Label("URL", systemImage: "link")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
                if unsub.has_mailto == true {
                    Label("Email", systemImage: "envelope")
                        .font(.caption2)
                        .foregroundColor(.purple)
                }

                Spacer()

                Button(action: { Task { await viewModel.cancelPending(unsub) } }) {
                    Text("Cancel")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(white: 0.92))
                        .clipShape(Capsule())
                }

                Button(action: { Task { await viewModel.executePending(unsub) } }) {
                    Text("Unsub Now")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .overlay(
            Rectangle()
                .fill(Color(white: 0.95))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

// MARK: - Allowlist

private struct AllowlistSection: View {
    let entries: [AllowlistEntry]
    let isLoading: Bool
    let viewModel: MailFirewallViewModel
    let onAdd: () -> Void

    var body: some View {
        if isLoading && entries.isEmpty {
            ProgressView()
                .padding(.top, 40)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text("\(entries.count) entries")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.black)
                            .frame(width: 28, height: 28)
                            .background(Color(white: 0.95))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if entries.isEmpty {
                    EmptyStateView(title: "No allowlist entries", message: "Add patterns to always allow certain senders.")
                        .padding(.top, 16)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            AllowlistRow(entry: entry)
                                .swipeActions(edge: .trailing) {
                                    Button("Delete", role: .destructive) {
                                        Task { await viewModel.removeAllowlistEntry(entry) }
                                    }
                                }
                        }
                    }
                }
            }
        }
    }
}

private struct AllowlistRow: View {
    let entry: AllowlistEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.pattern ?? "")
                .font(.caption.weight(.semibold))
                .foregroundColor(.black)

            if let note = entry.note, !note.isEmpty {
                Text(note)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white)
        .overlay(
            Rectangle()
                .fill(Color(white: 0.95))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

// MARK: - Helpers

private func initials(for name: String) -> String {
    let parts = name.split(separator: " ")
    let first = parts.first?.first.map(String.init) ?? "?"
    let second = parts.dropFirst().first?.first.map(String.init) ?? ""
    return (first + second).uppercased()
}
