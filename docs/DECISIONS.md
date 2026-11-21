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

## ADR-008 — DNS resolution and destination pinning for feed transport
**Status:** Proposed — implementation spike in progress

The current URL validator is a conservative URL-shape filter only. It does not resolve hostnames or control which address the HTTP stack ultimately connects to. DNS rebinding and hostnames resolving to private or special-purpose addresses therefore remain an SSRF gap.

A future hardened transport must own both resolution and connection establishment. The implementation must not perform a standalone DNS lookup and then hand the original hostname to an ordinary URLSession, because that permits a second resolution during connection setup.

Required design properties:
- Resolve each hostname immediately before connecting and validate every returned A/AAAA address against the IANA special-purpose ranges. Reject the destination if the answer set contains any non-public address; do not let connection racing select an unchecked address.
- Connect to one of the validated numeric addresses directly, without resolving the hostname again.
- For HTTPS, preserve the original hostname for TLS SNI and certificate hostname verification while pinning the socket destination to the selected validated IP.
- Re-run the complete resolution and validation pipeline for every redirect destination. Retain the existing redirect count, response-size and timeout limits.
- Keep the transport behind a small injectable protocol so NEWSFLOWCore tests can use deterministic resolver and connection fakes. The app/platform adapter may use Network.framework or another transport that can demonstrably satisfy the TLS and address-pinning requirements.
- Do not silently fall back to ordinary URLSession for a hostname when pinning is unavailable. Fail closed.

### Implementation spike findings (2026-11-21)

The isolated `PinnedTLSConnectionFactory` creates an `NWConnection` to a numeric IPv4/IPv6 endpoint and configures the original validated DNS hostname for TLS SNI. The production feed path remains unchanged.

The controlled loopback TLS integration suite is now verified on iOS Simulator. Commit `16df70dc9fe3deb1ec43197ee6a211f902917432` passed Core Tests on Linux (27 tests), Core Tests on Apple Foundation, and iOS Simulator build/tests (8 tests; 0 failures). The three TLS integration cases passed: trusted hostname, hostname mismatch rejection and untrusted-chain rejection. The success case asserts SNI and the numeric loopback remote endpoint; cancellation is also exercised. Test-only trust configuration remains behind a DEBUG-only factory entry point. Production TLS retains default system trust evaluation.

A cross-platform `FeedIPAddress` value and conservative public-unicast policy have now been added to NEWSFLOWCore. `FeedIPAddressPolicy.validateAnswerSet` fails closed for empty, malformed or mixed public/non-public resolver answer sets. Unit tests cover ordinary public IPv4/IPv6 and private, loopback, link-local, shared, multicast, documentation, reserved and selected transition/special-purpose ranges. CI for these new files is pending; they are not yet considered verified.

No DNS resolver or production connection orchestration is implemented. The existing URLSession feed transport remains in place and remains subject to the documented DNS rebinding gap. See `docs/FEED_TRANSPORT_SPIKE.md` for exact files, tests and the current verification boundary.

See `docs/FEED_TRANSPORT_SPIKE.md` for the current implementation inventory, verification boundary, TLS test-harness requirements and remaining acceptance criteria.

ADR-008 remains proposed. Do not claim complete SSRF protection, replace the current feed transport or merge the hardening branch until the controlled TLS proof, DNS answer-set policy, redirect re-resolution, HTTP framing/bounded streaming, timeout and cancellation tests have passed.
