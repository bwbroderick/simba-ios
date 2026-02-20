import Foundation

@MainActor
final class MailFirewallViewModel: ObservableObject {
    @Published var stats: FirewallStats?
    @Published var reviewEmails: [FirewallEmail] = []
    @Published var blockedEntries: [BlockedEntry] = []
    @Published var pendingUnsubs: [PendingUnsubscribe] = []
    @Published var allowlist: [AllowlistEntry] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = MailFirewallService.shared

    func loadDashboard() async {
        isLoading = true
        errorMessage = nil
        do {
            async let s = service.fetchStats()
            async let r = service.fetchReviewEmails()
            stats = try await s
            reviewEmails = try await r
        } catch FirewallError.authRequired {
            service.showAuthWebView = true
        } catch is CancellationError {
            // Ignore — SwiftUI refreshable cancels tasks
        } catch {
            if !error.isCancelled { errorMessage = error.localizedDescription }
        }
        isLoading = false
    }

    func loadReview() async {
        isLoading = true
        errorMessage = nil
        do {
            reviewEmails = try await service.fetchReviewEmails()
        } catch FirewallError.authRequired {
            service.showAuthWebView = true
        } catch is CancellationError {
        } catch {
            if !error.isCancelled { errorMessage = error.localizedDescription }
        }
        isLoading = false
    }

    func loadBlocked() async {
        isLoading = true
        errorMessage = nil
        do {
            blockedEntries = try await service.fetchBlocked()
        } catch FirewallError.authRequired {
            service.showAuthWebView = true
        } catch is CancellationError {
        } catch {
            if !error.isCancelled { errorMessage = error.localizedDescription }
        }
        isLoading = false
    }

    func loadPending() async {
        isLoading = true
        errorMessage = nil
        do {
            pendingUnsubs = try await service.fetchPending()
        } catch FirewallError.authRequired {
            service.showAuthWebView = true
        } catch is CancellationError {
        } catch {
            if !error.isCancelled { errorMessage = error.localizedDescription }
        }
        isLoading = false
    }

    func loadAllowlist() async {
        isLoading = true
        errorMessage = nil
        do {
            allowlist = try await service.fetchAllowlist()
        } catch FirewallError.authRequired {
            service.showAuthWebView = true
        } catch is CancellationError {
        } catch {
            if !error.isCancelled { errorMessage = error.localizedDescription }
        }
        isLoading = false
    }

    // MARK: - Actions

    func approveEmail(_ email: FirewallEmail) async {
        reviewEmails.removeAll { $0.id == email.id }
        do {
            _ = try await service.approveEmail(id: email.id)
            await refreshStats()
        } catch FirewallError.authRequired {
            service.showAuthWebView = true
        } catch {
            if !error.isCancelled {
                errorMessage = error.localizedDescription
                await loadReview()
            }
        }
    }

    func approveOnce(_ email: FirewallEmail) async {
        reviewEmails.removeAll { $0.id == email.id }
        do {
            _ = try await service.approveOnce(id: email.id)
            await refreshStats()
        } catch FirewallError.authRequired {
            service.showAuthWebView = true
        } catch {
            if !error.isCancelled {
                errorMessage = error.localizedDescription
                await loadReview()
            }
        }
    }

    func rejectEmail(_ email: FirewallEmail) async {
        reviewEmails.removeAll { $0.id == email.id }
        do {
            _ = try await service.rejectEmail(id: email.id)
            await refreshStats()
        } catch FirewallError.authRequired {
            service.showAuthWebView = true
        } catch {
            if !error.isCancelled {
                errorMessage = error.localizedDescription
                await loadReview()
            }
        }
    }

    func unblock(_ entry: BlockedEntry) async {
        blockedEntries.removeAll { $0.fingerprint == entry.fingerprint }
        guard let fingerprint = entry.fingerprint else { return }
        do {
            _ = try await service.unblock(fingerprint: fingerprint)
            await refreshStats()
        } catch FirewallError.authRequired {
            service.showAuthWebView = true
        } catch {
            if !error.isCancelled {
                errorMessage = error.localizedDescription
                await loadBlocked()
            }
        }
    }

    func cancelPending(_ unsub: PendingUnsubscribe) async {
        pendingUnsubs.removeAll { $0.message_id == unsub.message_id }
        guard let messageId = unsub.message_id else { return }
        do {
            _ = try await service.cancelPending(messageId: messageId)
            await refreshStats()
        } catch FirewallError.authRequired {
            service.showAuthWebView = true
        } catch {
            if !error.isCancelled {
                errorMessage = error.localizedDescription
                await loadPending()
            }
        }
    }

    func executePending(_ unsub: PendingUnsubscribe) async {
        pendingUnsubs.removeAll { $0.message_id == unsub.message_id }
        guard let messageId = unsub.message_id else { return }
        do {
            _ = try await service.executePending(messageId: messageId)
            await refreshStats()
        } catch FirewallError.authRequired {
            service.showAuthWebView = true
        } catch {
            if !error.isCancelled {
                errorMessage = error.localizedDescription
                await loadPending()
            }
        }
    }

    func addAllowlistEntry(pattern: String, note: String?) async {
        do {
            _ = try await service.addAllowlistEntry(pattern: pattern, note: note)
            await loadAllowlist()
            await refreshStats()
        } catch FirewallError.authRequired {
            service.showAuthWebView = true
        } catch {
            if !error.isCancelled { errorMessage = error.localizedDescription }
        }
    }

    func removeAllowlistEntry(_ entry: AllowlistEntry) async {
        allowlist.removeAll { $0.pattern == entry.pattern }
        guard let pattern = entry.pattern else { return }
        do {
            _ = try await service.removeAllowlistEntry(pattern: pattern)
            await refreshStats()
        } catch FirewallError.authRequired {
            service.showAuthWebView = true
        } catch {
            if !error.isCancelled {
                errorMessage = error.localizedDescription
                await loadAllowlist()
            }
        }
    }

    private func refreshStats() async {
        do {
            stats = try await service.fetchStats()
        } catch {
            // Silent fail on stats refresh
        }
    }
}

private extension Error {
    /// Check for both CancellationError and URLError.cancelled
    var isCancelled: Bool {
        self is CancellationError || (self as? URLError)?.code == .cancelled
    }
}
