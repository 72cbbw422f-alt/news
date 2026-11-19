# NEWSFLOW — Product plan

**Product:** NEWSFLOW  
**Target:** iPhone first; iPad adaptation after core UX  
**Positioning:** A native, local-first personal content reader  
**Reference:** Reeder's unified reading model, without copying its implementation, branding or visual assets.

## Product scope (Full)

### P0 — Release foundation
- SwiftUI navigation and design system.
- Source management: add/edit/delete, enable/disable, folder assignment.
- RSS 2.0 and Atom ingestion.
- Background/manual refresh with per-source errors and last-refresh state.
- Unified chronological timeline.
- Article detail reader with readable typography and system share.
- Unread/read state, mark all read, save/bookmark, reading history.
- Search title, summary and source; filters for unread/saved/source/folder.
- Offline persistence and duplicate detection.
- Import/export OPML.
- Robust empty, loading, offline and error states.
- Accessibility, Dynamic Type, VoiceOver and dark mode.
- Unit tests for parsing, normalization, deduplication and state transitions.

### P1 — Media
- Podcast RSS discovery and episode list.
- Playback controls, playback position, speed, skip intervals and background audio.
- YouTube channel/video feed support using documented/public interfaces where available.
- Open video in supported player or YouTube app; do not promise unsupported background playback.

### P2 — Social and discovery
- Bluesky via AT Protocol public APIs; account authentication only if needed and explicitly approved.
- Reddit integration through supported endpoints and applicable API terms.
- Per-integration rate limiting, caching and graceful degradation.
- Unified timeline controls and source-specific filters.

### P3 — Apple ecosystem
- Home Screen and Lock Screen widgets (only data available to widget extension).
- Share extension for saving URLs.
- Optional notifications with user-configurable schedules and source filters.
- Optional iCloud/CloudKit sync with conflict handling and a clear local-only mode.
- iPad layouts and keyboard shortcuts.

## Explicit non-goals for 1.0
- No mandatory NEWSFLOW account.
- No proprietary server required to read RSS.
- No scraping that bypasses access controls or violates service terms.
- No AI summaries in the Full scope; that belongs to a later optional edition.
- No claim that every website exposes a full article body in RSS. Where a feed only contains an excerpt, provide a reliable open-original action and an optional, carefully scoped reader extraction strategy.

## Delivery gates

| Gate | Exit criteria |
|---|---|
| G0 Product & architecture | Requirements, data contracts, platform minimum and privacy model documented |
| G1 Core package | Parser handles RSS/Atom fixtures; tests pass; malformed feeds fail safely |
| G2 Persistence | Sources/articles persist; stable IDs and deduplication verified |
| G3 RSS MVP | Add source, refresh, unified timeline, read/save/search all work |
| G4 Reader polish | Article rendering, accessibility, offline/error states and OPML |
| G5 Media | Podcast playback and supported YouTube experience tested |
| G6 Social | Bluesky/Reddit adapters comply with API constraints and have rate-limit handling |
| G7 Release candidate | Device testing, performance, crash checks, signing and install instructions |

## Definition of done

A feature is not done because a screen exists. It is done when:
1. Its data contract and failure modes are defined.
2. It works with realistic and malformed input.
3. Loading, empty, offline and error states are covered.
4. State survives app relaunch where expected.
5. Accessibility and Dynamic Type are checked.
6. Automated tests pass and manual test steps are documented.
7. No secrets, private tokens or personal data are committed.

## Working method

- Work in small, reviewable commits on feature branches.
- Keep `main` stable.
- Record material decisions in `DECISIONS.md`.
- Update this plan and the changelog as scope/status changes.
- Never describe a build as tested unless an actual build/test was run on a compatible environment.