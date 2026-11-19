# Changelog

All notable project changes are recorded here.

## Unreleased — Phase 1 foundation
- Replaced placeholder README with project overview and development instructions.
- Added phased product plan, architecture, architecture decisions and quality gates.
- Added standalone NEWSFLOWCore Swift package.
- Added FeedSource and Article domain models.
- Added RSS 2.0 / Atom XML parsing and relative-link resolution.
- Added bounded asynchronous HTTP transport with timeout, response-size and redirect limits.
- Added feed refresh normalization and duplicate counting.
- Added article merge policy that preserves local identity, first-seen date, read state and saved state.
- Added parser, transport, model and merge-policy unit tests.
- Added GitHub Actions workflow using the official Swift 6.2.1 container.
- Added repository ignore rules for Xcode, SwiftPM and signing artifacts.

### Verification
- GitHub Actions run [44576849855](https://github.com/72cbbw422f-alt/news/actions/runs/44576849855) passed.
- 9 tests executed, 0 failures, on Swift 6.2.1 / Linux.

### Known limitations
- The iOS application target, SwiftData persistence, OPML and reader UI are not implemented yet.
- Redirect validation currently checks HTTP(S) schemes and redirect count; private-network destination blocking and DNS rebinding defenses remain hardening work.
- No iOS build or IPA has been produced.
