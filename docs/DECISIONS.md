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
**Status:** Proposed — implementation spike required

The current URL validator is a conservative URL-shape filter only. It does not resolve hostnames or control which address the HTTP stack ultimately connects to. DNS rebinding and hostnames resolving to private or special-purpose addresses therefore remain an SSRF gap.

A future hardened transport must own both resolution and connection establishment. The implementation must not perform a standalone DNS lookup and then hand the original hostname to an ordinary URLSession, because that permits a second resolution during connection setup.

Required design properties:
- Resolve each hostname immediately before connecting and validate every returned A/AAAA address against the IANA special-purpose ranges. Reject the destination if the answer set contains any non-public address; do not let connection racing select an unchecked address.
- Connect to one of the validated numeric addresses directly, without resolving the hostname again.
- For HTTPS, preserve the original hostname for TLS SNI and certificate hostname verification while pinning the socket destination to the selected validated IP.
- Re-run the complete resolution and validation pipeline for every redirect destination. Retain the existing redirect count, response-size and timeout limits.
- Keep the transport behind a small injectable protocol so NEWSFLOWCore tests can use deterministic resolver and connection fakes. The app/platform adapter may use Network.framework or another transport that can demonstrably satisfy the TLS and address-pinning requirements.
- Do not silently fall back to ordinary URLSession for a hostname when pinning is unavailable. Fail closed.

The implementation spike must prove, with integration tests, the actual peer address used by the connection, hostname-based TLS validation, mixed public/private DNS answers, IPv4 and IPv6 handling, redirect re-resolution, cancellation and bounded streaming. Until those tests pass, keep the current DNS limitation explicit and do not claim complete SSRF protection.
