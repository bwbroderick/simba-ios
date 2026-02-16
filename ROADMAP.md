# Simba iOS — Production Roadmap

This document defines the implementation plan to take Simba from its current Phase 1 MVP to a production-grade email client. Features are organized into prioritized phases with estimated complexity and implementation guidance.

> **Excluded from scope:** Mark as unread, email signatures, multi-account support, app lock/biometrics, end-to-end encryption (S/MIME/PGP), all accessibility (VoiceOver, Dynamic Type, High Contrast, Reduce Motion), internationalization/localization, dark mode theming, iPad/Split View support, iOS widgets, Spotlight indexing, and Share Extension.

---

## Phase 2 — Core Email Completeness

These are blocking gaps that prevent real daily-driver usage. Ship these before any public release.

### 2.1 Attachments

**Priority: Critical | Complexity: High**

Attachments are table-stakes for any email client. Users cannot function without viewing or sending files.

**Viewing Attachments (Inbound)**
- Parse `multipart/*` MIME parts from Gmail API `payload.parts` recursively.
- Detect attachment parts via `Content-Disposition: attachment` or `filename` in headers.
- Display attachment chips (filename, size, file type icon) below the email body in `EmailDetailView` and `EmailCardView`.
- Tap to preview inline using `QuickLook` (`QLPreviewController` via UIKit bridge) for common types: PDF, images, Office docs, plain text.
- "Save to Files" action using `UIDocumentPickerViewController` for export.
- Download attachments on-demand via `GET /gmail/v1/users/me/messages/{messageId}/attachments/{attachmentId}`.
- Show download progress indicator for large files.
- Cache downloaded attachments to disk with size-limited eviction (e.g., 200MB cap).

**Sending Attachments (Outbound)**
- Add attachment button in `ComposeView`, `ReplyComposeView`, and `ForwardComposeView`.
- File picker via `UIDocumentPickerViewController` (Files app) and `PHPickerViewController` (Photos).
- Display attached files as removable chips in compose UI.
- Encode attachments as base64 MIME parts in the RFC 2822 message body.
- Enforce Gmail's 25MB send limit with user-facing validation.
- Handle `multipart/mixed` (attachments) and `multipart/alternative` (HTML + plain text body) MIME construction.

**Files to modify:** `GmailViewModel.swift`, `GmailThreadLoader.swift`, `Models.swift`, `EmailDetailView.swift`, `Components.swift` (ComposeView, ReplyComposeView, ForwardComposeView, EmailCardView).
**New files:** `AttachmentService.swift`, `AttachmentPreviewView.swift`.

---

### 2.2 Labels & Folders (Mailbox Navigation)

**Priority: Critical | Complexity: Medium**

Users currently only see INBOX. They need access to the rest of their mailbox.

**Implementation:**
- Add a mailbox navigation drawer or tab system accessible from the side drawer (`SideDrawerView`).
- Fetch system labels from `GET /gmail/v1/users/me/labels`.
- Support built-in mailboxes: Inbox, Sent, Drafts, Trash, Spam, Starred, All Mail.
- Display custom user labels as additional sections.
- Modify `fetchThreads()` in `GmailViewModel` to accept a `labelId` parameter instead of hardcoding `INBOX`.
- Show current mailbox name in `HeaderView`.
- Add "Move to" action on threads — `POST /gmail/v1/users/me/threads/{id}/modify` with `addLabelIds`/`removeLabelIds`.
- Add label pills/chips on email cards showing applied labels.

**Files to modify:** `GmailViewModel.swift`, `InboxView.swift`, `Components.swift` (SideDrawerView, HeaderView, EmailCardView), `Models.swift`.
**New files:** `MailboxListView.swift`.

---

### 2.3 Archive & Star Actions

**Priority: Critical | Complexity: Low**

Core email triage actions missing from the current UI.

**Archive:**
- Remove `INBOX` label via `POST /gmail/v1/users/me/threads/{id}/modify` with `removeLabelIds: ["INBOX"]`.
- Add archive button to `EmailDetailView` action bar and swipe actions (see Phase 3.6).
- Animate card removal from inbox on archive.

**Star/Flag:**
- Toggle `STARRED` label via the modify endpoint.
- Add star icon to `EmailCardView` and `EmailDetailView`.
- Visual state: filled star (starred) vs outline star (unstarred).
- Starred view accessible from mailbox navigation (Phase 2.2).

**Files to modify:** `GmailViewModel.swift`, `EmailDetailView.swift`, `Components.swift` (EmailCardView).

---

### 2.4 Pagination & Infinite Scroll

**Priority: Critical | Complexity: Medium**

The app loads a maximum of 20 emails. Real inboxes have thousands.

**Implementation:**
- Store `nextPageToken` from Gmail API list response.
- Detect scroll-near-bottom in `InboxView` using a `LazyVStack` with an `onAppear` trigger on a sentinel view.
- Fetch next page with `pageToken` parameter appended to the threads list request.
- Append new threads to existing array (don't replace).
- Show loading spinner at bottom during fetch.
- Apply same pagination to search results in `SearchView`.
- Apply pagination to label/folder views.
- Handle edge case: thread moves between pages during pagination (deduplicate by `threadID`).

**Files to modify:** `GmailViewModel.swift`, `InboxView.swift`, `SearchView.swift`.

---

### 2.5 CC/BCC in Compose

**Priority: Critical | Complexity: Low**

Basic compose completeness — CC and BCC are expected in any email client.

**Implementation:**
- Add optional CC and BCC fields to `ComposeView` and `ReplyComposeView`.
- Toggle CC/BCC visibility with a "Show CC/BCC" button to keep UI clean by default.
- Support multiple recipients in each field (reuse contact picker pattern from `ForwardComposeView`).
- Include `Cc:` and `Bcc:` headers in RFC 2822 message construction.
- Parse and display CC recipients in received email headers in `EmailDetailView`.

**Files to modify:** `Components.swift` (ComposeView, ReplyComposeView), `GmailViewModel.swift` (send logic), `EmailDetailView.swift`.

---

### 2.6 Drafts

**Priority: High | Complexity: Medium**

Users expect to save work-in-progress emails and resume them later.

**Implementation:**
- Auto-save drafts on a timer (every 30s) and on compose view dismiss.
- Use `POST /gmail/v1/users/me/drafts` to create drafts and `PUT /gmail/v1/users/me/drafts/{id}` to update.
- `GET /gmail/v1/users/me/drafts` to list drafts in the Drafts mailbox.
- `DELETE /gmail/v1/users/me/drafts/{id}` on successful send.
- Resume draft: populate compose view from draft data.
- Show draft indicator in inbox if a thread has an associated draft.
- Prompt user "Save as draft?" on compose dismiss if content exists.

**Files to modify:** `GmailViewModel.swift`, `Components.swift` (ComposeView, ReplyComposeView).
**New files:** `DraftService.swift`.

---

## Phase 3 — Reliability, Performance & UX Polish

These items make the app feel solid and trustworthy. Ship alongside or shortly after Phase 2.

### 3.1 Push Notifications

**Priority: High | Complexity: High**

Users expect to know about new emails without opening the app.

**Implementation:**
- Register for APNs in `AppDelegate` and request notification permission.
- Set up a lightweight backend service (or use Firebase Cloud Messaging as a relay) to receive Gmail push notifications.
- Gmail Push: Use `POST /gmail/v1/users/me/watch` with a Google Cloud Pub/Sub topic to receive real-time mailbox change notifications.
- On notification receipt, perform a delta sync (see 3.2) to fetch new messages.
- Display notification with sender, subject, and preview text.
- Notification actions: Reply, Archive, Mark as Read (using `UNNotificationCategory`).
- Update app badge count with unread count from `GET /gmail/v1/users/me/labels/INBOX` (unread count in response).
- Renew watch subscription every 7 days (Gmail watch expires).

**Backend requirement:** A server component is needed to receive Pub/Sub messages and forward to APNs. Consider Firebase Cloud Functions or a minimal server.

**New files:** `NotificationService.swift`, `PushNotificationHandler.swift`.
**Files to modify:** `AppDelegate.swift`, `GmailViewModel.swift`.

---

### 3.2 Incremental Sync (Delta Sync)

**Priority: High | Complexity: High**

The app currently refetches everything on every refresh, which is slow and wasteful.

**Implementation:**
- Store `historyId` from the most recent Gmail API response.
- On refresh, use `GET /gmail/v1/users/me/history?startHistoryId={id}` to get only changes since last sync.
- Process history records: `messagesAdded`, `messagesDeleted`, `labelsAdded`, `labelsRemoved`.
- Apply changes incrementally to local thread cache.
- Fall back to full fetch if `historyId` is too old (404 response).
- Use `historyId` in conjunction with push notifications (Phase 3.1) for efficient real-time sync.

**Files to modify:** `GmailViewModel.swift`, `Models.swift` (add `historyId` to cache model).

---

### 3.3 Offline Support & Background Refresh

**Priority: High | Complexity: Medium**

Users should be able to read cached emails offline and have fresh data when they open the app.

**Offline Improvements:**
- Detect network state with `NWPathMonitor` and show an offline banner.
- Queue actions (send, archive, trash, star) taken while offline.
- Replay queued actions when connectivity returns (with conflict detection).
- Expand cache to cover current mailbox view, not just inbox.
- Cache thread detail (full messages) for recently viewed threads.

**Background Refresh:**
- Register `BGAppRefreshTask` in `Info.plist` and `AppDelegate`.
- Schedule periodic refresh (iOS decides actual timing).
- On background fetch, perform delta sync and update cache.
- Update badge count silently.

**New files:** `NetworkMonitor.swift`, `OfflineActionQueue.swift`.
**Files to modify:** `GmailViewModel.swift`, `AppDelegate.swift`, `InboxView.swift`, `Info.plist`.

---

### 3.4 Error Handling & Resilience

**Priority: High | Complexity: Medium**

Replace raw error strings with a robust, user-friendly error system.

**Implementation:**
- Define an `AppError` enum with categorized cases: `networkUnavailable`, `authExpired`, `rateLimited`, `serverError`, `parseError`, etc.
- Map Gmail API HTTP status codes to `AppError` cases (401 → `authExpired`, 429 → `rateLimited`, 5xx → `serverError`).
- User-facing error messages: friendly copy with suggested actions ("Check your connection and try again").
- Toast/banner error display (non-blocking) for transient errors vs. full-screen error state for fatal issues.
- Automatic retry with exponential backoff for 429 and 5xx responses (max 3 retries).
- Token refresh on 401, then retry the original request once.
- Network reachability check before API calls — show offline state immediately rather than waiting for timeout.

**New files:** `AppError.swift`, `ErrorBannerView.swift`.
**Files to modify:** `GmailViewModel.swift`, `GmailThreadLoader.swift`, `InboxView.swift`.

---

### 3.5 Performance Optimization

**Priority: Medium | Complexity: Medium**

Make the app fast and efficient, especially for large mailboxes.

**Concurrent Thread Loading:**
- Replace sequential thread detail fetching with `TaskGroup`-based concurrent loading (cap at 5 concurrent requests).
- Show threads as they load rather than waiting for all to complete.

**Search Debouncing:**
- Debounce search input by 300ms before firing API requests.
- Cancel in-flight search requests when query changes.

**HTML Rendering:**
- Lazy-render HTML snapshots (only for visible cards + 2 ahead).
- Monitor memory pressure via `UIApplication.didReceiveMemoryWarningNotification` and evict caches.
- Track and log render times for performance monitoring.

**Image Loading in HTML:**
- Implement lazy image loading in `InteractiveHTMLView` via WKWebView content rules.
- Optional: block remote images by default with a "Load images" button for privacy/performance.

**Code Organization:**
- Break `Components.swift` (1,497 lines) into individual component files.
- Group into `Components/` directory: `AvatarView.swift`, `EmailCardView.swift`, `ComposeView.swift`, `SideDrawerView.swift`, etc.

**Files to modify:** `GmailViewModel.swift`, `SearchView.swift`, `Components.swift` (split), `InteractiveHTMLView.swift`, `HTMLSnapshotCache.swift`.

---

### 3.6 Swipe Actions

**Priority: Medium | Complexity: Low**

Swipe gestures are the primary email triage interaction on mobile.

**Implementation:**
- Add `.swipeActions` modifiers to email cards in `InboxView`.
- Leading swipe: Archive (green).
- Trailing swipe: Trash (red), Star (yellow/orange).
- Haptic feedback on swipe threshold via `UIImpactFeedbackGenerator`.
- Animate card removal after destructive actions.
- Undo toast for archive/trash with 5-second window before committing the API call.

**Files to modify:** `InboxView.swift`, `Components.swift` (EmailCardView), `GmailViewModel.swift`.

---

### 3.7 Undo Send

**Priority: Medium | Complexity: Low**

Give users a safety net after sending an email.

**Implementation:**
- After `sendEmail()`, show an "Undo" toast/banner for a configurable delay (default 5 seconds).
- Delay the actual `messages.send` API call during the undo window.
- If user taps Undo, cancel the send and return to compose view with content preserved.
- Store the delay preference in `UserDefaults` (0s, 5s, 10s, 30s).
- Settings option to configure the undo delay.

**Files to modify:** `GmailViewModel.swift`, `Components.swift` (ComposeView, ReplyComposeView).
**New files:** `UndoToastView.swift`.

---

### 3.8 Onboarding Flow

**Priority: Medium | Complexity: Low**

First-time users need context about the app's social-feed-style email experience.

**Implementation:**
- 3-4 screen onboarding carousel shown on first launch (track via `UserDefaults`).
- Screens: Welcome/value prop → Card-based feed explanation → Swipe actions tutorial → Sign in with Gmail.
- Skip button and page indicator dots.
- Transition directly into Gmail OAuth sign-in on the final screen.

**New files:** `OnboardingView.swift`.
**Files to modify:** `ContentView.swift` (conditional root view).

---

## Phase 4 — Observability, Testing & CI/CD

These items are essential for sustainable development and safe iteration.

### 4.1 Testing Foundation

**Priority: High | Complexity: High**

Zero tests is a critical gap. Build a testing foundation before adding more features.

**Unit Tests:**
- Add a `SimbaTests` target to the Xcode project (`project.yml`).
- Test `TextChunker` — chunking logic, edge cases (empty string, single word, very long text).
- Test date/time formatting and relative timestamp logic.
- Test RFC 2822 message construction (To, CC, BCC, Subject, Body, Attachments).
- Test `ContactStore` — extraction, deduplication, search filtering.
- Test MIME parsing — extracting attachments, nested multipart, HTML body selection.
- Test `AppError` mapping from HTTP status codes.
- Test `OfflineActionQueue` — enqueue, dequeue, replay.
- Test cache serialization/deserialization round-trips.

**ViewModel Tests:**
- Mock `URLSession` with `URLProtocol` subclass for deterministic API responses.
- Test `GmailViewModel` — fetch, send, archive, star, trash, draft operations.
- Test pagination state machine (initial load, next page, deduplication).
- Test error handling paths (401 refresh, 429 retry, offline queue).

**UI Tests:**
- Add a `SimbaUITests` target.
- Test critical flows: sign in → view inbox → open thread → reply → send.
- Test compose flow with attachments.
- Test search flow.
- Test swipe actions.

**Snapshot Tests (Optional):**
- Use `swift-snapshot-testing` for visual regression on key components.

**New files:** `SimbaTests/` directory with test files mirroring source structure.
**Config changes:** `project.yml` (add test targets).

---

### 4.2 CI/CD Pipeline

**Priority: High | Complexity: Medium**

Automated builds and tests prevent regressions and enable safe shipping.

**GitHub Actions Workflow:**
- Build the project on every PR and push to main.
- Run unit tests and report results.
- Run UI tests on iOS Simulator.
- Lint with SwiftLint (add as SPM plugin or build phase).
- Code coverage reporting (e.g., Codecov integration).
- Cache SPM dependencies and derived data for faster builds.

**Fastlane (Release Automation):**
- `fastlane test` — run all tests.
- `fastlane beta` — build and upload to TestFlight.
- `fastlane release` — build and submit to App Store.
- Manage signing with `match` (certificates and provisioning profiles).

**New files:** `.github/workflows/ci.yml`, `Gemfile`, `fastlane/Fastfile`, `.swiftlint.yml`.

---

### 4.3 Logging & Crash Reporting

**Priority: High | Complexity: Low**

Visibility into production issues is essential.

**Structured Logging:**
- Use `os.Logger` with subsystem and category for structured logging.
- Define log categories: `network`, `auth`, `cache`, `ui`, `sync`.
- Log API requests/responses (sanitized — no tokens or email content in production).
- Log cache hits/misses and eviction events.
- Log error paths with context.

**Crash Reporting:**
- Integrate Firebase Crashlytics (or Sentry).
- Capture non-fatal errors for API failures, parse errors, etc.
- Include breadcrumbs: last screen viewed, last action taken, network state.

**Analytics (Basic):**
- Track key events: app open, email read, reply sent, search performed, attachment downloaded.
- Screen view tracking for navigation patterns.
- Funnel: inbox → thread → reply → send (measure drop-off).

**New files:** `Logger.swift`, `AnalyticsService.swift`.
**Config changes:** SPM dependencies (Firebase/Crashlytics or Sentry).

---

## Phase 5 — Security & Trust

### 5.1 Tracking & Privacy Protection

**Priority: Medium | Complexity: Medium**

Protect users from email tracking and enhance trust.

**Remote Image Blocking:**
- Block remote image loading in HTML emails by default.
- Show "Images blocked" banner with "Load images" button.
- Per-sender allow-list stored in `UserDefaults` ("Always load images from this sender").
- Strip tracking pixels (1x1 images, known tracker domains).

**Link Protection:**
- Intercept link taps in `InteractiveHTMLView`.
- Show link preview sheet before opening: display actual URL, highlight domain mismatches.
- Optional: check against Google Safe Browsing API for known phishing URLs.

**Files to modify:** `InteractiveHTMLView.swift`, `Components.swift` (EmailCardView).
**New files:** `PrivacySettings.swift`, `LinkPreviewSheet.swift`.

---

### 5.2 Secure Configuration

**Priority: Medium | Complexity: Low**

Harden the app's credential and configuration management.

**Implementation:**
- Move OAuth Client ID from source code to a `GoogleService-Info.plist` excluded from version control (`.gitignore`).
- Add `GoogleService-Info.plist.example` with placeholder values for developer setup.
- Clear all caches (email cache, HTML snapshots, contact store) on sign-out.
- Explicitly revoke OAuth tokens on sign-out via `GIDSignIn.sharedInstance.disconnect()`.
- Add SSL certificate pinning for Gmail API domain (optional, advanced).

**Files to modify:** `GmailViewModel.swift`, `AppDelegate.swift`, `SimbaApp.swift`, `.gitignore`.

---

### 5.3 Rate Limiting (Client-Side)

**Priority: Low | Complexity: Low**

Prevent accidental rapid-fire actions and protect against API abuse.

**Implementation:**
- Debounce destructive actions (trash, archive, send) — disable button for 1s after tap.
- Throttle API calls: max 10 requests/second to Gmail API.
- Queue excess requests and process sequentially.
- Show "Slow down" feedback if user triggers throttle.

**Files to modify:** `GmailViewModel.swift`.

---

## Phase 6 — App Store Readiness

### 6.1 Rich Text Compose

**Priority: Medium | Complexity: High**

Compose is currently plain text only. Users expect basic formatting.

**Implementation:**
- Formatting toolbar above keyboard: Bold, Italic, Underline, Strikethrough, Lists (bullet/numbered), Links.
- Use `NSAttributedString` or a lightweight rich text editor (e.g., embedded `WKWebView` with `contentEditable`).
- Convert formatted content to HTML for the email body.
- Support `multipart/alternative` with both `text/plain` and `text/html` parts.
- Inline image insertion from Photos.

**New files:** `RichTextEditor.swift`, `FormattingToolbar.swift`.
**Files to modify:** `Components.swift` (ComposeView, ReplyComposeView).

---

### 6.2 Snooze

**Priority: Low | Complexity: Medium**

Let users defer emails to resurface later.

**Implementation:**
- Snooze action in email detail and swipe actions.
- Preset options: Later today, Tomorrow, Next week, Pick date/time.
- Use local `UNNotificationRequest` scheduled for snooze time.
- On notification fire, move thread back to inbox (remove snooze label, add inbox label).
- Show snoozed emails in a "Snoozed" section (custom label or local tracking).
- Requires either a custom Gmail label for snoozed state or local-only tracking with `UserDefaults`/Core Data.

**New files:** `SnoozeService.swift`, `SnoozeDatePicker.swift`.
**Files to modify:** `GmailViewModel.swift`, `EmailDetailView.swift`.

---

### 6.3 Batch Operations (Multi-Select)

**Priority: Low | Complexity: Medium**

Power users need to triage multiple emails at once.

**Implementation:**
- Long-press on email card to enter selection mode.
- Checkbox overlay on each card in selection mode.
- "Select All" / "Deselect All" in toolbar.
- Batch action bar at bottom: Archive, Trash, Star, Mark Read, Move to Label.
- Execute actions concurrently with `TaskGroup` (cap at 10 concurrent).
- Show progress indicator for large batch operations.
- Exit selection mode after action completes.

**Files to modify:** `InboxView.swift`, `GmailViewModel.swift`, `Components.swift` (EmailCardView).

---

### 6.4 App Store Submission Prep

**Priority: High (at ship time) | Complexity: Low**

Checklist for App Store review compliance.

- [ ] Privacy Policy URL hosted and linked in App Store Connect.
- [ ] App Store description, keywords, and category.
- [ ] Screenshots for required device sizes (6.7", 6.1", 5.5").
- [ ] Google OAuth app verification (move out of "Testing" mode, submit for Google review).
- [ ] App privacy nutrition labels in App Store Connect (data types collected/used).
- [ ] Review `Info.plist` for required usage descriptions (camera, photos, files if used).
- [ ] Bump version from 0.1.0 to 1.0.0.
- [ ] TestFlight beta testing round before submission.

---

## Implementation Order Summary

| Order | Item | Phase | Priority | Complexity |
|-------|------|-------|----------|------------|
| 1 | Attachments (view & send) | 2.1 | Critical | High |
| 2 | Labels & Folders | 2.2 | Critical | Medium |
| 3 | Archive & Star | 2.3 | Critical | Low |
| 4 | Pagination | 2.4 | Critical | Medium |
| 5 | CC/BCC | 2.5 | Critical | Low |
| 6 | Drafts | 2.6 | High | Medium |
| 7 | Error Handling | 3.4 | High | Medium |
| 8 | Performance Optimization | 3.5 | Medium | Medium |
| 9 | Swipe Actions | 3.6 | Medium | Low |
| 10 | Incremental Sync | 3.2 | High | High |
| 11 | Offline Support | 3.3 | High | Medium |
| 12 | Testing Foundation | 4.1 | High | High |
| 13 | CI/CD Pipeline | 4.2 | High | Medium |
| 14 | Logging & Crash Reporting | 4.3 | High | Low |
| 15 | Push Notifications | 3.1 | High | High |
| 16 | Undo Send | 3.7 | Medium | Low |
| 17 | Tracking Protection | 5.1 | Medium | Medium |
| 18 | Secure Configuration | 5.2 | Medium | Low |
| 19 | Onboarding | 3.8 | Medium | Low |
| 20 | Rich Text Compose | 6.1 | Medium | High |
| 21 | Snooze | 6.2 | Low | Medium |
| 22 | Batch Operations | 6.3 | Low | Medium |
| 23 | Rate Limiting | 5.3 | Low | Low |
| 24 | App Store Prep | 6.4 | High* | Low |

*High priority at ship time, not during development.

---

## Architecture Notes

**As the app grows, consider these structural changes:**

1. **Modularize `Components.swift`** (Phase 3.5) — Split into individual files under a `Components/` directory before adding more UI.
2. **Introduce a Network Layer** — Abstract `URLSession` calls behind a `GmailAPIClient` protocol for testability and separation of concerns.
3. **Consider Core Data or SwiftData** — The current JSON file cache won't scale for offline support, drafts, and snoozed state. A proper persistence layer (SwiftData for iOS 17+) would simplify cache management, querying, and migration.
4. **Service Layer** — Extract business logic from `GmailViewModel` (666 lines) into focused services: `MailboxService`, `ComposeService`, `SyncService`, `CacheService`.
5. **Dependency Injection** — Use SwiftUI `@Environment` or a lightweight DI container to inject services, enabling testability and previews.
