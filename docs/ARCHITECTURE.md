# NEWSFLOW — Architecture

## Layers

```
SwiftUI App
  ├─ Features (Timeline, Reader, Library, Sources, Search, Settings)
  ├─ Presentation state / view models
  └─ Design system
       ↓
Domain
  ├─ FeedSource, Article, Folder, ReadingState
  ├─ Repository protocols
  └─ Use cases (Refresh, MarkRead, Save, Search, ImportOPML)
       ↓
Data
  ├─ RSS/Atom parser
  ├─ Bounded HTTP feed client and refresh coordinator
  ├─ Persistence adapter (SwiftData)
  └─ Integration adapters (Podcast, YouTube, Bluesky, Reddit)
```

## Key boundaries
- UI must not parse XML or issue ad-hoc network requests.
- Domain models should not depend on SwiftUI.
- Network responses are untrusted input. Enforce timeouts, size limits and safe redirect handling.
- Source adapters normalize provider-specific data into common domain records.
- Persistence is accessed through repository interfaces, not directly from views.
- External integrations are independently optional; failure in one must not block RSS.

## Core entities

### FeedSource
- Stable UUID.
- Canonical feed URL and optional website URL.
- User-facing title, description and icon URL.
- Folder assignment, enabled state and refresh metadata.
- Per-source parse/network error state.

### Article
- Stable internal UUID.
- Source relationship and provider identifier.
- Canonical URL, title, summary/content, author and publication date.
- First-seen and updated timestamps.
- Read state, saved state and optional reading position.
- Content hash for duplicate detection.

### Reading state
Read/saved state belongs to the user's local library, not the feed payload. Refreshing a feed must never reset it.

## RSS ingestion pipeline
1. Validate URL scheme (HTTP/HTTPS only).
2. Open a Network.framework connection using the original hostname.
3. Wait for readiness, inspect the actual remote peer and reject private/local/reserved addresses before sending HTTP request bytes.
4. For HTTPS, complete TLS using the original hostname and normal system trust before peer inspection. The TLS handshake may reach a disallowed peer; no HTTP request bytes may be sent before validation.
5. Fetch with bounded timeouts, header limits, streaming response-size limits and redirect revalidation.
6. Parse RSS 2.0 or Atom with external entity resolution disabled.
7. Normalize whitespace, dates, links and HTML fragments.
8. Resolve stable identity: GUID/Atom ID, otherwise canonical URL, otherwise deterministic fallback.
9. Deduplicate within source and merge updated metadata without overwriting user reading state.
10. Persist transactionally.
11. Record last attempt, last success and a user-readable error.

## Reliability and security
- Never execute feed HTML or scripts.
- Render remote HTML in a restricted reader context; external links open through system browser.
- Sanitize HTML before display and block automatic remote media loads by default where practical.
- Do not log full article bodies, credentials or private feed URLs.
- Keep API credentials in Keychain; do not commit secrets.
- Respect API terms, rate limits and user authorization for third-party services.
- Background refresh is best-effort under iOS scheduling; manual refresh remains available.
- Use cancellation and per-source concurrency limits to avoid runaway refreshes.
- Feed and redirect URLs reject non-HTTP(S) schemes, embedded credentials, non-standard ports, local/reserved hostnames, IPv6 literals and non-public IPv4 literals.
- The production transport must inspect the actual connected peer and validate it before sending HTTP bytes. HTTPS TLS handshake traffic can occur before that inspection; this limitation is explicit.
- Redirects must establish a new connection and repeat peer validation. Never reuse a previously validated peer decision for a new hostname or redirect hop.
- Do not fall back to URLSession after a peer-validation failure.
- The current production URLSession feed client still resolves hostnames itself and does not expose a pre-request peer-validation hook. DNS rebinding/private-peer mitigation is therefore not yet active in production.

## Sync strategy
Start local-first. Add CloudKit only after local persistence semantics are stable. Sync must define conflict resolution for read/saved state, source edits, deletions and duplicate merges. Users must be able to continue in local-only mode.

## Platform strategy
- iOS app: SwiftUI.
- Core package: Foundation + FoundationXML; no UI dependencies.
- Persistence: SwiftData in the app layer.
- Minimum iOS version to be finalized when the Xcode project is created; target iOS 17+ unless device compatibility testing suggests otherwise.
- Build and signing require Xcode/macOS. A source repository alone is not an IPA.
