# Feed transport hardening — implementation spike

**Date:** 2026-11-21  
**Status:** Production direction selected; connect-by-name peer-validation transport not yet implemented  
**Branch:** `security/feed-url-hardening`

## Selected architecture

ADR-008 now selects Apple Network.framework connect-by-name, followed by inspection and validation of the actual connected remote endpoint **before any HTTP request bytes are sent**.

The system resolver and operating system retain control of DNS, address selection, Happy Eyeballs, VPN/network path, IPv6 and DNS64/NAT64. NEWSFLOW does not perform a separate DNS lookup and then ask a second networking stack to resolve the hostname again.

Security boundary:
- HTTP request bytes are withheld until the established peer is confirmed to be a public unicast address.
- For HTTPS, the TLS handshake necessarily occurs before the application can inspect the connected peer. Some TCP/TLS traffic may therefore reach a private or special-purpose endpoint before NEWSFLOW disconnects it.
- This is not strict pre-connect blocking. It is an explicit application-layer SSRF mitigation, not a claim that no network contact can occur.

## Why the previous numeric-pinning prototype is not the production direction

The current branch includes:
- `AppleSystemFeedAddressResolver` using separate synchronous IPv4/IPv6 `getaddrinfo` calls.
- `PinnedTLSConnectionFactory` connecting to numeric IP addresses while retaining the original TLS hostname.
- `PinnedFeedConnectionFactory` preparing connections from returned resolver candidates.

These pieces are useful experiments, but they do not establish a complete authoritative A+AAAA answer set, cannot interrupt an active `getaddrinfo` call, and require the app to own address racing and platform network-path compatibility. Apple's TN3151 warns about resolve-then-connect designs and VPN On Demand behavior. Keep these prototypes isolated; do not integrate them into production FeedHTTPClient.

## Implementation contract

1. Validate the URL before connecting.
2. Create a Network.framework connection using the original hostname.
3. For HTTPS, use the original hostname for TLS SNI and normal certificate identity/trust validation.
4. Wait for connection readiness, then inspect the actual remote endpoint.
5. Require a numeric peer address and validate it with Core's shared `FeedIPAddressPolicy`.
6. Cancel immediately if the peer is private, local, reserved, malformed or cannot be inspected.
7. Do not send HTTP request bytes before peer validation succeeds.
8. Bound request/response headers, body bytes, timeouts and redirects.
9. On every redirect, close the old connection and repeat URL validation, connect-by-name and peer validation.
10. Propagate cancellation to the active connection. No URLSession fallback is allowed.

## Required test harness

- Use a local Network.framework server to capture whether any HTTP bytes arrive before peer validation.
- Verify public peer acceptance and private/loopback peer rejection.
- Verify trusted TLS hostname success, SNI, hostname mismatch rejection and untrusted-chain rejection.
- Verify redirect revalidation, bounded streaming, malformed framing, timeout and cancellation.
- Add explicit tests for HTTP and HTTPS separately; HTTPS peer validation occurs after TLS readiness.
- Treat simulator tests as necessary but insufficient for VPN On Demand, IPv6-only, DNS64/NAT64 and network changes.

## Existing verified work

The numeric-IP TLS prototype has previously passed iOS Simulator integration tests for SNI, actual numeric peer endpoint, valid hostname, hostname mismatch, untrusted chain and cancellation.

Commit `14e29598cff47639762286747ca67a357c90561a` passed:
- Core Tests — Linux.
- Core Tests — Apple Foundation.
- iOS Simulator build and XCTest.

The system-resolver adapter and numeric-IP connection-preparation tests also passed in that CI run. Those results do not verify the newly selected connect-by-name peer-validation transport, which is not yet implemented.

Production FeedHTTPClient remains on URLSession. No signed IPA or physical-device verification is included.
