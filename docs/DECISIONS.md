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

A cross-platform `FeedIPAddress` value and conservative public-unicast policy have been added to NEWSFLOWCore. `FeedIPAddressPolicy.validateAnswerSet` fails closed for empty, malformed or mixed public/non-public resolver answer sets. Unit tests cover ordinary public IPv4/IPv6 and private, loopback, link-local, shared, multicast, documentation, reserved and selected transition/special-purpose ranges. On commit `62c827decd994063cf9cfe49c56998caef5fd07a`, all six new IP policy tests passed on Linux and Apple Foundation; the full Core suites passed (33 Linux tests, 35 Apple Foundation tests), and the iOS Simulator build/tests passed (8 tests, 0 failures). The policy is verified as implemented, but it is not a DNS resolver or complete IANA-registry-derived production policy.

The injectable, cancellation-aware resolver contract and fail-closed Core orchestration are now implemented in NEWSFLOWCore. The service validates the DNS hostname, checks task cancellation before and after resolution, and validates the entire returned address set before exposing numeric destinations. Deterministic fake-resolver tests cover valid dual-stack results, invalid hostnames, empty/malformed/mixed answer sets, resolver errors and cancellation while the resolver is suspended. Commit `6acb11359342139ed1bd6d17cc403c5f911fad12` passed Core Linux, Core Apple Foundation and iOS Simulator push CI.

The Apple resolver adapter is **not** implemented. The initial `DNSServiceGetAddrInfo` candidate has no documented one-shot completion signal for the complete initial A+AAAA set: `kDNSServiceFlagsMoreComing` only reports queued callbacks, and the query otherwise remains active until deallocated. Its timeout flag terminates with a timeout error even if answers were previously delivered. `CFHost` is currently deprecated by Apple, while POSIX `getaddrinfo` is synchronous and cannot be assumed to return the complete dual-stack set in one call. Do not implement an adapter using a quiet-period heuristic or claim complete DNS validation from partial results.

The next decision gate is to identify a supported Apple resolver approach that can both establish a complete A+AAAA answer set and be actively cancelled. A hostname-based Network.framework connection followed by remote-peer inspection was also evaluated: for TLS connections, the ready state follows the TLS handshake, so the private destination has already received handshake traffic before validation. A TCP-only connection could be checked before HTTP bytes, but there is no documented in-place TLS upgrade for that established connection; Secure Transport is deprecated and is not an acceptable replacement. This alternative is documented but not approved because it weakens the pre-connect guarantee. If no suitable system API exists, revisit the transport/security architecture explicitly. The existing URLSession feed transport remains in place and remains subject to the documented DNS rebinding gap.

See `docs/FEED_TRANSPORT_SPIKE.md` for the API evaluation, implementation inventory, verification boundary, TLS test-harness requirements and remaining acceptance criteria.

ADR-008 remains proposed. Do not claim complete SSRF protection, replace the current feed transport or merge the hardening branch until the controlled TLS proof, DNS answer-set policy, redirect re-resolution, HTTP framing/bounded streaming, timeout and cancellation tests have passed.


### DNS-over-HTTPS candidate evaluation — 2026-11-21

RFC 8484 DoH provides a bounded HTTP exchange for each DNS wire query, making separate A and AAAA responses parseable and cancellable at the HTTP task level. It is technically viable as an application-managed resolver, but it does not preserve system DNS semantics automatically: a third-party resolver receives feed-hostname queries, may bypass VPN/split-DNS/filtering choices, and introduces endpoint bootstrap, provider availability, redirects, failover and DNS wire-parser requirements. Separate A and AAAA responses are not an atomic snapshot; CNAME handling, RCODE, truncation, TTL and DNSSEC semantics must be explicit.

Apple's NetworkExtension DNS settings configure encrypted DNS at the system level after explicit user activation; the reviewed API documentation does not expose a per-query complete A+AAAA result set and cancellation contract to the app. This is not a direct implementation of `FeedAddressResolving`.

**Decision:** Do not silently introduce a third-party DoH provider or make DoH the default. The architecture decision must explicitly choose between preserving system/VPN DNS behavior with a weaker guarantee that validates every address actually returned by the system resolver and connects only to a validated numeric endpoint, or an opt-in application-managed DoH mode with provider and privacy disclosure. Neither option is implemented yet. The existing URLSession feed transport remains unchanged and retains the documented SSRF/DNS-rebinding limitation.

See `docs/FEED_TRANSPORT_SPIKE.md` for the detailed trade-offs and protocol requirements.


### DNS-over-HTTPS candidate — 2026-11-21

DoH (RFC 8484) is the strongest resolver candidate identified so far because each HTTPS exchange returns a bounded DNS wire message. Explicit A and AAAA queries can be parsed independently, then combined under a fail-closed policy. The DNS response code, question, answer records, CNAME chain and truncation/malformed conditions must be validated; HTTP 2xx alone is not DNS success. Cancellation, response bounds, timeouts and redirect restrictions must be enforced.

DoH does not create an atomic A+AAAA snapshot, and it changes the privacy/trust model: feed hostnames are disclosed to a third-party resolver, and the app bypasses the device's configured resolver (including VPN/custom/managed DNS). TLS to the DoH server is not DNSSEC validation. The resolver endpoint also needs a trusted bootstrap and normal TLS validation. Apple DNS Settings APIs configure user-enabled system-wide DNS and are not an app-local resolver API; DNS Proxy is a separate system extension architecture.

**Decision:** candidate only; not approved as the default. Before implementation, explicitly decide whether the product accepts an external resolver and its privacy implications, choose the provider and bootstrap strategy, define dual-stack/CNAME completeness and failure semantics, and select a maintained DNS wire-format parser. See `docs/FEED_TRANSPORT_SPIKE.md` for the full evaluation and references.


### System resolver candidate: separate AF_INET / AF_INET6 lookups — 2026-11-21

Apple TN3151 recommends the system DNS resolver and `getaddrinfo` for BSD-socket applications. Apple's archived guidance warns that one dual-stack `getaddrinfo` call may cancel outstanding IPv6 work shortly after an IPv4 success. Two concurrent family-constrained calls (`AF_INET` and `AF_INET6`) may avoid that cross-family behavior and preserve system/VPN DNS routing better than app-managed DoH.

This remains a candidate only. `getaddrinfo` is synchronous and cannot be actively interrupted by Swift task cancellation; a cancelled caller could avoid connecting after resolution returns, but the resolver work may continue. The two results are not an atomic DNS snapshot and do not prove authoritative completeness. Any candidate used for a connection must be validated as a numeric address and passed to the pinned transport, never re-resolved by hostname. The strict whole-answer-set rejection policy must not be weakened to selected-endpoint-only validation without an explicit ADR decision.

**Next experiment:** prototype the resolver behind the existing injectable protocol in an isolated branch or test target, with bounded worker management and cancellation/no-connect guarantees. Test on supported iOS versions and real IPv4/IPv6/VPN/DNS failure scenarios before deciding whether its weaker cancellation semantics are acceptable.

References:
- Apple TN3151: https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api
- Apple archived hostname resolution guidance: https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/NetworkingTopics/Articles/ResolvingDNSHostnames.html
- RFC 8305: https://www.rfc-editor.org/rfc/rfc8305


### Apple swift-async-dns-resolver evaluation — 2026-11-21

Apple's `swift-async-dns-resolver` 0.8.1 exposes A and AAAA queries and supports iOS 13+, but source review shows it does not currently satisfy the strict resolver contract. Its default Darwin backend still uses DNS-SD, calls `DNSServiceProcessResult` once and deallocates the query; complete multi-response answer-set semantics are not established. Its c-ares backend promptly cancels the awaiting task, but intentionally leaves the underlying DNS request running until callback/timeout rather than cancelling the resolver operation. It is therefore not approved as a drop-in production resolver. Adoption would require an explicit relaxation of active cancellation and additional proof of A/AAAA and CNAME completeness. Full source review is recorded in `docs/FEED_TRANSPORT_SPIKE.md`.


### Upstream c-ares backend readiness risk — 2026-11-21

Apple's `swift-async-dns-resolver` latest release is 0.8.1. Upstream PR [#93](https://github.com/apple/swift-async-dns-resolver/pull/93) remains open and reports a Darwin TCP readiness defect in the c-ares polling loop: sockets are passed to `ares_process_fd` based on interest rather than OS readiness, which can cause in-progress TCP handshakes to be treated as connected and fail with a spurious connection-refused error. The proposed fix is not included in the latest release.

This adds a release-quality concern to the previously identified limitations: DNS-SD answer completion remains unproven, c-ares task cancellation does not cancel the underlying request, and the released c-ares TCP path has an unresolved upstream issue. Do not adopt 0.8.1. Re-evaluate only after a fixed upstream release and successful NEWSFLOW-specific iOS tests; cancellation and answer-set semantics must still be addressed independently.


### Follow-up: resolver cancellation and system-resolver alternative — 2026-11-21

A source-level review of Apple swift-async-dns-resolver 0.8.1 confirms that c-ares cancellation resumes the caller promptly but leaves the underlying query running until callback/timeout. The library deliberately avoids `ares_cancel` because its shared channel and poll loop make cancellation prone to cross-query effects and deadlock. A dedicated channel alone does not prove safe active cancellation; a fork would require a redesigned serialized cancellation/event-loop model.

Apple's archived iOS guidance also documents that `getaddrinfo` is synchronous and may cancel outstanding IPv6 work after a successful IPv4 response. It cannot satisfy the current complete-A+AAAA-RRset requirement. However, a different SSRF security contract may be possible: validate every numeric candidate actually returned by the system resolver and connect only to one of those validated numeric endpoints. This prevents a second hostname resolution and prevents use of an unchecked destination, but it does not prove that every record in the authoritative A+AAAA RRset was returned. It also carries synchronous cancellation, VPN On Demand, Happy Eyeballs and NAT64/DNS64 considerations under Apple's TN3151.

**Decision remains Proposed.** Before implementation, explicitly choose between strict full-RRset validation (with DoH or a purpose-built resolver) and validating all system-resolver candidates actually returned (weaker completeness contract, with additional platform constraints). No fallback to hostname-based URLSession is permitted under either option. Full details are in `docs/FEED_TRANSPORT_SPIKE.md`.
