# Architecture decision records

## ADR-001 — Native SwiftUI
**Status:** Accepted  
Use SwiftUI for the iOS UI. It gives native navigation, accessibility, Dynamic Type, widgets and system integration without a web wrapper.

## ADR-002 — Local-first, no mandatory account
**Status:** Accepted  
The core RSS reader must work without an account or paid backend. This keeps recurring costs at zero for the basic experience and preserves user control.

## ADR-003 — Swift Package for domain/feed core
**Status:** Accepted  
Keep parsing and core models in a standalone Swift Package so they can be tested independently of the app UI.

## ADR-004 — Standards-first feeds
**Status:** Accepted  
Support RSS 2.0 and Atom first. Podcast feeds use RSS enclosures and podcast namespaces as a later extension.

## ADR-005 — Optional cloud sync
**Status:** Accepted  
Do not make CloudKit a prerequisite for the MVP. Add it after local data behavior and conflict rules are tested.

## ADR-006 — Integrations are adapters
**Status:** Accepted  
YouTube, Bluesky and Reddit remain separate adapters. Their availability, rate limits and terms can change independently; core RSS must remain usable without them.

## ADR-007 — No fabricated build status
**Status:** Accepted  
Only report compilation, tests, IPA creation or device verification when the corresponding operation was actually performed in a compatible environment.