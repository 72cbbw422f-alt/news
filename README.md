# NEWSFLOW

**A personal, native Apple content reader.**

NEWSFLOW is a Reeder-inspired iOS app focused on bringing RSS/news, saved reading, podcasts, video and social feeds into one calm, fast, user-controlled reading experience.

> Build a genuinely useful reader first. Expand integrations only when the core is reliable.

## Product principles
- Native iOS experience built with SwiftUI.
- Local-first: reading and saved content remain available on-device.
- Standards-first integrations (RSS 2.0, Atom, Podcast RSS).
- No mandatory subscription and no proprietary backend required for core use.
- Privacy by design: no tracking, no account required for local use.
- Accessible, responsive, polished light and dark appearances.
- Clear separation between source adapters, domain logic, persistence and UI.

## Current status
**Phase 1 — foundation in progress.** This branch establishes product requirements, architecture decisions, a reusable core package and parser tests. It is not yet a compiled iOS app or an IPA.

- [Project plan](docs/PROJECT_PLAN.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Architecture decisions](docs/DECISIONS.md)
- [Quality gates](docs/QUALITY.md)
- [Changelog](CHANGELOG.md)

## Planned feature set
1. Unified timeline and source subscriptions.
2. RSS 2.0 and Atom ingestion, refresh, deduplication and unread state.
3. Full article reader, reading list, bookmarks and history.
4. Folders, tags, search and smart filters.
5. Podcast feeds and playback.
6. YouTube channel/video discovery using supported public interfaces.
7. Bluesky and Reddit integrations, subject to API policies and rate limits.
8. iOS widgets, share extension, notifications and optional iCloud sync.

## Development
The reusable core is a Swift Package in `NEWSFLOWCore/`. Run its tests on macOS or Linux with a compatible Swift toolchain:

```sh
cd NEWSFLOWCore
swift test
```

The iOS application target and signing/build pipeline follow after core contracts and tests are stable. A source repository alone is not an IPA; building and signing the iOS app requires Xcode on macOS.
