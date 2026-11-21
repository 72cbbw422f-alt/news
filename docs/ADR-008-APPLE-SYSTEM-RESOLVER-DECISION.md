# ADR-008 — Apple system DNS and numeric destination pinning

**Decision date:** 2026-11-21  
**Status:** Proposed — prototype only; production architecture is not approved  
**Branch:** `security/feed-url-hardening`

## Status clarification

The current branch contains an isolated implementation prototype for Apple's configured system resolver and numeric-IP TLS connection preparation. Approval to prototype these components is **not** approval to replace the production feed transport.

The latest CI run for commit `14e29598cff47639762286747ca67a357c90561a` passed:
- NEWSFLOW Core Tests — Linux.
- NEWSFLOW Core Tests — Apple Foundation.
- NEWSFLOW iOS Build — simulator build and XCTest.

These results verify compilation and automated tests in the configured CI environments. They do not verify VPN On Demand, IPv6-only/DNS64/NAT64, network changes, resolver completeness, or real-device behavior.

## Candidate architecture under evaluation

The prototype uses the Apple device's configured system DNS resolver for feed hostname resolution. It does not silently use a third-party DNS-over-HTTPS provider or override the user's configured DNS, VPN, managed DNS or split-DNS environment.

The resolver adapter collects numeric IPv4 and IPv6 candidates. Every candidate returned by the resolver must pass the existing conservative `FeedIPAddressPolicy`. If the returned candidate set is empty, malformed, or contains any non-public/special-purpose address, the destination is rejected.

The connection prototype connects only to a validated numeric IP endpoint. It does not pass the original hostname to a second resolver during connection establishment. For HTTPS, the original DNS hostname remains the TLS SNI and certificate identity, with normal system trust and hostname verification.

This is an evaluated candidate, not a production commitment. The production `FeedHTTPClient` remains on `URLSession`.

## Explicit security boundary

Apple's system resolver does not provide NEWSFLOW with a documented guarantee that the returned results are the complete authoritative A+AAAA RRset. The prototype therefore validates **every numeric candidate returned by the system resolver**, but does not claim that it has inspected records the system resolver did not return.

This is weaker than the original strict full-RRset requirement. It is not equivalent to authoritative complete-answer validation. No production security claim may imply otherwise.

A cancelled lookup must never lead to a connection. The synchronous system resolver call itself cannot be interrupted once running; the async adapter cancels the awaiting caller promptly, discards late results, and Core orchestration checks cancellation again before returning any destination to the transport.

## Platform and compatibility constraints

- Preserve the system resolver path so configured VPN, custom DNS and managed DNS policies are not silently bypassed.
- Do not implement a quiet-period heuristic around DNS-SD callbacks.
- Do not use deprecated CFHost as the production resolver.
- Do not add a third-party DoH dependency or provider endpoint without an explicit architecture decision.
- Keep IPv4 and IPv6 candidates; IPv6-only and DNS64/NAT64 behavior requires real-device/network verification.
- Apple TN3151 warns that resolve-then-connect designs can affect VPN On Demand and require correct Happy Eyeballs behavior. A custom numeric-IP transport must account for those platform responsibilities; they cannot be assumed away by simulator tests.
- No fallback to hostname-based URLSession is permitted after resolution, validation or pinned-connection failure if strict destination pinning remains the chosen security contract.
- The alternative connect-by-name Network.framework APIs do not expose a documented pre-connect hook to validate every destination candidate. Inspecting the peer after readiness is too late to prevent connection/TLS traffic to a disallowed destination.

## Decision gates before production implementation

The team must explicitly choose and document which security contract is required:

1. **Strict full RRset + cancellable resolution:** use a resolver/transport design that can establish a reliable answer-set completion boundary and inspect all relevant candidates before connecting. This may require a maintained DNS implementation and carries privacy, compatibility and operational costs.
2. **System resolver + validate every returned candidate:** accept that the resolver may not expose the complete authoritative A+AAAA set and that resolve-then-connect introduces Apple platform compatibility responsibilities.
3. **Connect-by-name + post-connect peer validation:** accept the weaker guarantee that TCP/TLS connection traffic may reach a disallowed endpoint before the app can inspect the peer. This is not equivalent to pre-connect SSRF prevention.

No option is selected for production by this ADR revision. The product/security owner must explicitly approve the threat-model trade-off before the transport is wired into production.

## Prototype implementation sequence

1. Keep the Apple system-resolver adapter and numeric-IP TLS factory isolated behind their current interfaces.
2. Maintain deterministic tests for candidate validation, cancellation, TLS identity, peer endpoint and trust failures.
3. Do not begin a production HTTP/1.1 transport until the decision gates above are resolved.
4. If numeric pinning is approved, implement bounded HTTP framing, streaming body limits, redirects with per-hop resolution/validation/pinning, address racing and active connection cancellation.
5. Test IPv4, IPv6, IPv6-only, DNS64/NAT64, VPN On Demand, DNS failures, cancellation and network changes on real Apple devices.
6. Keep the current URLSession feed path until all selected transport acceptance gates pass.

## Current verification and limitations

- Core resolver orchestration and conservative candidate-set validation have CI coverage.
- The numeric-IP TLS factory and controlled TLS integration tests have passed iOS Simulator CI.
- The Apple resolver adapter and `PinnedFeedConnectionFactory` compile and pass the current CI suite, including candidate preparation and mixed public/private rejection.
- The latest CI run passed Linux Core tests, Apple Foundation Core tests, and the iOS Simulator build/XCTest job.
- Production FeedHTTPClient remains on URLSession.
- DNS rebinding/SSRF risk is not yet closed in production.
- System resolver answer completeness and cancellability are not guaranteed.
- VPN On Demand, Happy Eyeballs, IPv6-only, DNS64/NAT64 and network-change behavior are not verified on real devices.
- No signed IPA or physical-device verification is included.

## References

- Apple TN3151 — Choosing the right networking API: https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api
- Apple archived Resolving DNS Hostnames guidance: https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/NetworkingTopics/Articles/ResolvingDNSHostnames.html
- Apple Supporting IPv6: https://developer.apple.com/support/ipv6
- RFC 8305 — Happy Eyeballs Version 2: https://www.rfc-editor.org/rfc/rfc8305
