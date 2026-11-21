# ADR-008 — Feed transport and private-network destination policy

**Decision date:** 2026-11-21  
**Status:** Accepted — Apple-native connect-by-name with pre-HTTP peer validation  
**Branch:** `security/feed-url-hardening`

## Decision

NEWSFLOW will use Network.framework connect-by-name for feed connections. The operating system remains responsible for DNS resolution, address selection, Happy Eyeballs behavior, VPN/network path integration, IPv6 and DNS64/NAT64 handling.

NEWSFLOW will inspect the established connection's actual remote endpoint and apply the shared `FeedIPAddressPolicy` **before sending any HTTP request bytes**. If the remote endpoint cannot be represented as a numeric IP address, or is private, local, reserved or otherwise non-public, the connection is cancelled and no HTTP request is sent.

For HTTPS, TLS is established using the original URL hostname and normal system certificate trust/hostname verification. Only after TLS reaches ready and the actual remote endpoint passes policy may NEWSFLOW send the HTTP request. For plain HTTP, the remote endpoint must pass policy after TCP readiness and before the request is sent.

This is the selected production direction. It replaces the resolve-then-connect system-resolver prototype as the preferred architecture. The existing `AppleSystemFeedAddressResolver`, `PinnedFeedConnectionFactory` and numeric-IP TLS spike remain isolated experiments and must not be wired into the production path.

## Explicit security boundary

This decision does **not** claim strict pre-connect destination validation.

Network.framework resolves and establishes the connection before NEWSFLOW can inspect the effective peer. For HTTPS, TLS handshake traffic may reach the selected endpoint before the application can reject it. The guarantee is narrower and precise:

- No HTTP request line, headers, cookies, credentials or feed request body are sent until the connected peer has passed destination policy.
- A disallowed peer is disconnected immediately after the connection becomes inspectable.
- TCP connection attempts and, for HTTPS, TLS handshake traffic may still reach a private or special-purpose endpoint before rejection.
- This is a meaningful SSRF mitigation for HTTP application-layer access, but it is not equivalent to preventing all network contact with private destinations.

The application must never silently fall back to URLSession or retry through a different unvalidated transport after peer validation fails.

## Why this choice

The strict numeric-pinning design requires a complete pre-connect DNS candidate set, then a connection to a selected numeric endpoint while preserving the original TLS identity. Apple's supported system APIs do not provide a reliable, cancellable complete A+AAAA answer-set boundary for this design. The synchronous `getaddrinfo` prototype cannot be interrupted and separate family queries are not an atomic authoritative RRset.

Resolve-then-connect also transfers address racing, network changes and VPN On Demand compatibility responsibilities from the system to the application. Apple's TN3151 warns against this pattern for ordinary Apple-platform application networking.

A custom DNS-over-HTTPS resolver could provide explicit DNS records, but it would introduce a separate resolver trust/privacy choice and may bypass the user's configured DNS, VPN, managed DNS or split-DNS behavior. That is not justified for the initial RSS product.

Connect-by-name preserves Apple's network path and address selection behavior. Inspecting the actual connected peer before sending HTTP bytes provides a clear, testable application-layer security boundary without pretending to provide strict pre-connect blocking.

## Required implementation contract

1. Validate URL syntax, scheme, credentials, port and hostname before opening a connection.
2. Create a Network.framework connection using the original hostname, not a separately resolved numeric address.
3. For HTTPS, use TLS with the original hostname as SNI and certificate identity, with normal system trust.
4. Wait for the connection to become ready.
5. Read the actual connected remote endpoint from the established connection. Require a numeric IPv4 or IPv6 address.
6. Validate the peer with the shared `FeedIPAddressPolicy`.
7. If endpoint inspection or validation fails, cancel the connection before sending any HTTP bytes.
8. Only after successful peer validation, send the HTTP request with the original hostname in the Host header.
9. Bound connection time, total request time, response headers, response body and redirects. Stream the response under a strict byte limit.
10. On every redirect, close the previous connection and repeat URL validation, connect-by-name, peer inspection and policy validation for the new destination.
11. Propagate task cancellation to the active Network.framework connection and release all continuations exactly once.
12. Do not use URLSession as a fallback path.

## Required tests

- Public IPv4 and IPv6 peer endpoints are accepted.
- Loopback, private, link-local, shared, multicast, unspecified, documentation and reserved/special-purpose endpoints are rejected.
- No HTTP request bytes are written before the peer passes validation.
- A private peer is disconnected after readiness and receives no HTTP request.
- HTTPS uses the original hostname for SNI and certificate hostname verification.
- Hostname mismatch and untrusted certificate chains fail.
- Redirects revalidate the new connected peer; redirect to a private peer sends no HTTP request to that peer.
- Redirect count, header size, response size, timeout and cancellation limits are enforced.
- Cancellation closes the active connection and does not resume a continuation more than once.
- IPv4, IPv6, IPv6-only, DNS64/NAT64, VPN On Demand and network changes are tested on real Apple devices before release.

## Prototype disposition

The current branch's system-resolver and numeric-IP TLS prototype is not the selected production path. Keep it isolated until the connect-by-name peer-validation transport is implemented and tested. Do not delete it in this change; it remains useful as a comparison experiment.

## Verification status

Latest verified branch head before this documentation update: `29bbc3aee8dcfd1ec7e6a1ac6fd0ac5ea43c5e3e`. All six GitHub Actions check-runs passed, including the Xcode iOS Simulator build and XCTest job. The Xcode job reported 17 app tests with 0 failures; the hostname connection-factory suite contributed 5 tests with 0 failures.

The verified implementation at that head is limited to:
- The hostname-based `NWConnection` factory and TLS SNI configuration.
- Connected-peer endpoint extraction and shared Core policy validation.
- Factory/endpoint unit tests.

The connection lifecycle (`.ready` observation, timeout, cancellation and exactly-once completion), HTTP framing/request writing, bounded response parsing, redirect loop and production FeedHTTPClient integration are **not implemented**. Production FeedHTTPClient remains on URLSession, so DNS-rebinding/private-peer mitigation is not active in production.

These CI results verify the code present at the stated head; they do not verify the full selected transport or real-device networking behavior. No signed IPA or physical-device verification is included.


## References

- Apple TN3151 — Choosing the right networking API: https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api
- Apple Network framework: https://developer.apple.com/documentation/network
- Apple NWConnection state: https://developer.apple.com/documentation/network/nwconnection/state-swift.enum
- RFC 8305 — Happy Eyeballs Version 2: https://www.rfc-editor.org/rfc/rfc8305
