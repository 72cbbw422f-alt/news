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
**Phase 1 — foundation and first iOS shell.** The core feed pipeline, automated tests and initial SwiftUI app are implemented. The iOS target has successfully generated and compiled for the iOS Simulator in GitHub Actions.

- [Project plan](docs/PROJECT_PLAN.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Architecture decisions](docs/DECISIONS.md)
- [Quality gates](docs/QUALITY.md)
- [Changelog](CHANGELOG.md)

## Implemented core
- RSS 2.0 and Atom parsing.
- HTTP fetch with timeout, streamed byte limit, status and redirect checks.
- Refresh normalization and duplicate counting.
- Merge policy preserving read/saved state and local identity.
- OPML 2.0 import/export with nested folder paths.
- 15 automated core tests passing in GitHub Actions on Swift 6.2.1.

## iOS app
- SwiftUI tab navigation and a unified article timeline.
- Local SwiftData persistence for feeds and articles.
- Add, refresh and remove RSS/Atom sources.
- Article detail, saved articles and sharing.
- Timeline search across article title, summary, author and source.
- Timeline scopes for all, unread and saved articles.
- OPML import/export from Settings, with duplicate URL detection and folder-path preservation.
- XcodeGen project manifest and successful iOS Simulator build in CI.

The XcodeGen manifest is `project.yml`. On a Mac with Xcode installed:

```sh
brew install xcodegen
xcodegen generate
open NEWSFLOW.xcodeproj
```

Select the NEWSFLOW scheme and an iOS 17+ simulator to build. Device installation requires signing configured in Xcode. This repository does not currently contain a signed IPA.

## Core package tests
Run on macOS or Linux with Swift 6.2.1 or a compatible Swift toolchain:

```sh
cd NEWSFLOWCore
swift test
```

## Planned next
- Feed-folder browsing and management.
- Background refresh and refresh scheduling.
- Full article extraction and offline reading.
- Podcast playback.
- YouTube, Bluesky and Reddit adapters using supported APIs.
- Widgets, share extension and optional iCloud sync.
