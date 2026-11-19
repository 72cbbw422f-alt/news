# Changelog

All notable project changes are recorded here.

## Unreleased — Phase 1 foundation
- Added product roadmap, architecture, architecture decisions and engineering quality gates.
- Added standalone NEWSFLOWCore Swift Package with FeedSource and Article domain models.
- Added RSS 2.0 and Atom parsing with relative-link resolution.
- Added bounded asynchronous HTTP transport with timeout, response-size, status-code and redirect checks.
- Added feed refresh normalization and duplicate counting.
- Added article merge policy preserving local identity, first-seen date, read state and saved state.
- Added OPML 2.0 import/export with nested folder paths.
- Added first iOS SwiftUI shell: tab navigation, unified timeline, article detail, source management, saved library and settings.
- Added SwiftData persistence models for sources and articles.
- Added XcodeGen project manifest and local build instructions.
- Added GitHub Actions CI using the official Swift 6.2.1 container.

### Verification
- GitHub Actions run [44577167059](https://github.com/72cbbw422f-alt/news/actions/runs/44577167059) passed.
- 15 core tests executed, 0 failures, on Swift 6.2.1 / Linux.
- Core package compile and test verified. iOS SwiftUI/SwiftData target has not yet been compiled with Xcode or tested on a device.

### Known limitations
- Full article extraction, background refresh scheduling, search/filter UI and integrations are not implemented yet.
- Redirect validation enforces HTTP(S) and a redirect count, but private-network destination blocking and DNS rebinding defenses remain hardening work.
- No signed iOS build or IPA has been produced.
