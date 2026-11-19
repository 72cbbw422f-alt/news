# Changelog

All notable project changes are recorded here.

## Unreleased — Phase 1 foundation
- Replaced placeholder README with project overview and development instructions.
- Added phased product plan, architecture, architecture decisions and quality gates.
- Added standalone NEWSFLOWCore Swift package.
- Added FeedSource and Article domain models.
- Added initial RSS 2.0 / Atom XML parser.
- Added parser and URL-validation unit tests.
- Added repository ignore rules for Xcode, SwiftPM and signing artifacts.
- Added GitHub Actions workflow to run core package tests on pushes and pull requests.

### Known limitations
- The iOS application target, SwiftData persistence, HTTP refresh coordinator, OPML and reader UI are not implemented yet.
- GitHub Actions test results have not yet been observed; no successful test run is claimed.
