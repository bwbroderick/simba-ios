# Simba iOS App Design (Phase 1)

## Goal

Build a focused iPhone email client for Simba's first release. Phase 1 ships a clean inbox experience and a thread view that make email feel like a social feed. The app is a front-end for the Simba assistant, but the scope here is only email reading and replying.

## Product Scope (Phase 1)

### Must Have
- Email inbox with card-based feed.
- Thread view that preserves the same card+scroll paradigm.
- Read emails with swipeable horizontal pages when content is long.
- Reply action (UI only for now, no advanced AI actions).
- Basic search UI entry point (non-functional placeholder is OK).
- Avatar, subject, sender line, timestamp, and preview text.

### Later (Out of Scope for Phase 1)
- AI summaries, auto-replies, or agentic actions.
- Calendar, reminders, or tasks.
- Multi-account.
- Offline and sync optimizations.
- Complex inbox organization.

## Core Interaction Model

- Vertical scrolling for the feed and threads.
- Horizontal paging inside a card for long email bodies.
- Thread count displayed as a comment bubble; tap to expand into thread view.
- The thread view keeps the same visual language with nested replies.

## Visual Direction

Design a mobile email client UI using a card-based layout. Existing email clients feel stale and outdated. We will mirror a social media UI (Twitter/Threads-like) to make email feel alive and engaging.

### Style
- Minimal, high-contrast, and highly readable.
- minimal white space between cards, multiple cards visible at once.
- Subtle borders, light shadows, rounded corners.
- Clear hierarchy: sender, subject, timestamp, preview.

### Reference Notes
- Social feed layout with dense content, subtle separators, and lightweight UI chrome.
- Email cards should feel like posts in a feed, not a list of rows.
- Thread view should read like a comment chain.

## Information Architecture

### Inbox (Primary)
- List of email cards.
- Each card shows:
  - Sender avatar (initials).
  - Sender name and timestamp.
  - Bold subject.
  - Preview text in a content box.
  - Reply count (comment bubble).
  - Quick actions area (reply/delete/save) as the final horizontal page.

### Thread (Secondary)
- Same card design, stacked vertically.
- Indentation or minimal markers for nested replies.
- Reply bar pinned at bottom.

## Motion & Feel

- Subtle fade-in for screen transitions.
- Smooth horizontal paging with snap.
- Avoid unnecessary animations; keep the feed responsive.

## Accessibility

- Text sizes should be readable without zoom.
- Minimum contrast for text and borders.
- Clear tap targets on cards and actions.

## Phase 1 Deliverables

- SwiftUI app shell with Inbox and Thread screens.
- Static data and mock content for UI validation.
- Componentized UI elements (Card, Avatar, Header, ReplyBar).

## Open Questions

- What email backend will Phase 1 connect to first?
- Should the reply action open a full composer or a minimal reply sheet?
- Should search be a modal or a dedicated screen?
