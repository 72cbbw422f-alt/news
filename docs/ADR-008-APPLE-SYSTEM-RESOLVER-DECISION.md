# ADR-008 — Apple system DNS and numeric destination pinning

**Decision date:** 2026-11-21  
**Status:** Accepted for implementation; production transport remains blocked on acceptance tests  
**Branch:** `security/feed-url-hardening`

## Decision

NEWSFLOW will use the Apple device's configured system DNS resolver for feed hostname resolution. The app will not silently use a third-party DNS-over-HTTPS provider and will not override the user's configured DNS, VPN, managed DNS or split-DNS environment.

The resolver adapter will use the system resolver and collect numeric IPv4 and IPv6 candidates. Every candidate returned by the resolver must pass the existing conservative `FeedIPAddressPolicy`. If the returned candidate set is empty, malformed, or contains any non-public/special-purpose address, the destination is rejected.

The connection layer must connect only to one of those validated numeric IP endpoints. It must not pass the original hostname to a second resolver during connection establishment. For HTTPS, the original DNS hostname must remain the TLS SNI and certificate identity, with normal system trust and hostname verification.

## Explicit security boundary

Apple's system resolver does not provide NEWSFLOW with a documented guarantee that the returned results are the complete authoritative A+AAAA RRset. The application therefore validates **every numeric candidate returned by the system resolver**, but does not claim that it has inspected records the system resolver did not return.

This is a deliberate relaxation from the original strict full-RRset requirement. It is not equivalent to authoritative complete-answer validation. The security guarantee is narrower and must be described accurately in product and engineering documentation.

A cancelled lookup must never lead to a connection. The synchronous system resolver call itself cannot be interrupted once running; the async adapter must cancel the awaiting caller promptly, discard late results, and the Core orchestration must check cancellation again before returning any destination to the transport.

## Platform and compatibility constraints

- Preserve the system resolver path so configured VPN, custom DNS and managed DNS policies are not silently bypassed.
- Do not implement a quiet-period heuristic around DNS-SD callbacks.
- Do not use deprecated CFHost as the production resolver.
- Do not add a third-party DoH dependency or provider endpoint.
- Keep IPv4 and IPv6 candidates; test IPv6-only and DNS64/NAT64 environments before release.
- A custom numeric-IP transport still needs explicit address racing/fallback and network-path behavior testing. Apple TN3151 warns that resolve-then-connect designs can affect VPN On Demand and require correct Happy Eyeballs behavior. This remains a release gate, not an assumed compatibility property.
- No fallback to hostname-based URLSession is permitted after resolution, validation or pinned-connection failure.

## Implementation sequence

1. Implement the Apple system-resolver adapter behind `FeedAddressResolving`.
2. Verify cancellation returns promptly and that late resolver results cannot start a connection.
3. Wire the validated numeric candidates into the pinned TLS connection factory.
4. Implement bounded HTTP/1.1 framing, streaming, redirects and per-hop re-resolution.
5. Test IPv4, IPv6, IPv6-only, DNS64/NAT64, VPN On Demand, DNS failures, cancellation and network changes on real Apple devices.
6. Keep the current URLSession feed path until all transport acceptance gates pass.

## Verification status at decision time

- Core resolver orchestration and conservative candidate-set validation exist and have CI coverage.
- The numeric-IP TLS factory and controlled TLS integration tests exist and have passed iOS Simulator CI.
- The Apple resolver adapter has been introduced as an implementation prototype; it is not yet verified by CI.
- Production FeedHTTPClient remains on URLSession.
- DNS rebinding/SSRF risk is not yet closed in production.
- No signed IPA or physical-device verification is included.

## References

- Apple TN3151 — Choosing the right networking API: https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api
- Apple archived Resolving DNS Hostnames guidance: https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/NetworkingTopics/Articles/ResolvingDNSHostnames.html
- Apple Supporting IPv6: https://developer.apple.com/support/ipv6
- RFC 8305 — Happy Eyeballs Version 2: https://www.rfc-editor.org/rfc/rfc8305
