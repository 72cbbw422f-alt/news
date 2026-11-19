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
- Added timeline search across article title, summary, author and source.
- Added all/unread/saved timeline filters.
- Added SwiftData persistence models for sources and articles.
- Added XcodeGen project manifest and local build instructions.
- Added GitHub Actions core test and macOS iOS Simulator build workflows.

### Verification
- GitHub Actions core test run [44577167059](https://github.com/72cbbw422f-alt/news/actions/runs/44577167059) passed: 15 tests, 0 failures.
- GitHub Actions iOS build run [44578014541](https://github.com/72cbbw422f-alt/news/actions/runs/44578014541) passed.
- XcodeGen project generation, package resolution and iOS Simulator compilation all completed successfully.

### Known limitations
- Full article extraction, background refresh scheduling, feed-folder management UI and external integrations are not implemented yet.
- Redirect validation enforces HTTP(S) and a redirect count, but private-network destination blocking and DNS rebinding defenses remain hardening work.
- No signed iOS device build or IPA has been produced.
