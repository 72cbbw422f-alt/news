# Feed transport hardening — implementation spike

**Date:** 2026-11-20  
**Status:** TLS factory configuration tests added; live TLS behavior not yet verified  
**Branch:** security/feed-url-hardening

## Problem

FeedURLSafety validates URL syntax and literal IPs, but the current URLSession transport resolves DNS itself. A hostname that resolves to a private or special-purpose address can therefore bypass the current URL-shape checks. A separate DNS lookup followed by URLSession is not an acceptable fix: the HTTP stack may resolve the hostname again.

## Implemented prototype

The isolated prototype is in `NEWSFLOWApp/Infrastructure/Networking/PinnedTLSConnectionFactory.swift`.

- `PinnedIPAddress` parses numeric IPv4 and IPv6 literals into Network.framework address types.
- `PinnedTLSConnectionFactory.makeConnection(serverName:address:port:)` creates an `NWConnection` to the explicit numeric IP endpoint.
- The original DNS hostname is validated through `NEWSFLOWCore.DNSHostname` and passed to `sec_protocol_options_set_tls_server_name`.
- No trust override and no ordinary URLSession fallback are installed.
- The prototype is not connected to the production feed path.

## Test harness added

An iOS unit-test target, `NEWSFLOWAppTests`, is now declared in `project.yml`. The initial test suite in `NEWSFLOWAppTests/PinnedTLSConnectionFactoryTests.swift` covers:

- Parsing IPv4 and IPv6 address literals.
- Rejecting hostnames and malformed address literals as network destinations.
- Rejecting local-style TLS identities.
- Rejecting port zero.
- Constructing an NWConnection from a validated DNS identity and a numeric endpoint, without starting the connection.

These are configuration-construction unit tests only. They do **not** prove actual peer routing, emitted SNI, certificate hostname validation, trust-chain evaluation, connection establishment, timeout or cancellation.

The iOS workflow now runs the app simulator build and the iOS unit-test scheme on an available iPhone Simulator. CI results for this new target must be checked before treating the harness as build-verified.

## Required next proof: controlled TLS server

Before expanding into DNS or HTTP, add a controlled TLS server/client integration fixture. The proof must establish all of the following:

1. The client connects to the selected numeric IPv4/IPv6 endpoint without a second hostname lookup.
2. The server observes the expected peer address.
3. The ClientHello carries the original DNS hostname as SNI.
4. A certificate valid for that hostname succeeds under normal system trust evaluation.
5. A hostname mismatch fails.
6. An untrusted chain fails.
7. Cancellation and timeout terminate the connection and complete the test exactly once.

The certificate strategy must preserve normal trust evaluation. Do not make a test pass by adding a trust-all callback or disabling hostname verification. If a private test CA is used, isolate its trust configuration to the test environment and retain normal chain and hostname checks.

A local `NWListener` fixture is a candidate for the controlled server, but its TLS identity setup and trust-store isolation must be proven before treating it as an acceptance test.

## Candidate transport direction

1. Resolve the feed hostname immediately before connecting.
2. Validate the complete A and AAAA answer set. Reject the entire set if any address is non-public or special-purpose.
3. Select one validated address and construct a numeric IPv4/IPv6 endpoint. Do not pass the original DNS hostname as the network endpoint.
4. Configure TLS server name to the original URL hostname. Keep normal system trust evaluation enabled.
5. Establish the connection and assert in integration tests that the remote peer is the selected numeric address.
6. Send an HTTP/1.1 request with the original hostname in the Host header. Parse status, headers, content-length and chunked transfer encoding under strict byte/time limits.
7. On redirect, close the current connection and repeat resolution, validation, pinning and TLS setup for the new destination.
8. Propagate task cancellation to the active connection and resolver operation.

This remains a prototype direction, not an approved production implementation. API documentation and a successful simulator build do not prove complete connection, trust-evaluation and HTTP behavior.

## Required acceptance tests

### Resolver and address policy
- Public IPv4 and global-unicast IPv6 answers are accepted.
- Loopback, private, link-local, shared, multicast, unspecified, documentation and reserved/special-purpose ranges are rejected.
- Mixed public/private A or AAAA answer sets are rejected as a whole.
- Empty answers, malformed addresses and resolver failures fail closed.
- IPv4 and IPv6 endpoints are constructed without a second hostname resolution.

### Connection and TLS
- Test server records the actual peer destination; it must equal the selected validated IP.
- HTTPS uses the original hostname for SNI.
- Certificate chain and hostname mismatch both fail.
- A valid certificate for the original hostname succeeds when connecting to the pinned IP.
- No trust-all callback or ordinary URLSession fallback is permitted.

### HTTP lifecycle
- Redirects trigger a fresh DNS lookup and full address validation.
- Redirect to a private IP or a hostname resolving to a private IP is rejected before connecting.
- Redirect count is bounded.
- Content-Length and chunked bodies are bounded while streaming, not only after full buffering.
- Non-2xx responses, malformed HTTP framing and unsupported transfer encodings fail safely.
- Timeout and cancellation close the connection and release continuations exactly once.

## Architecture boundary

Keep URL/address policy and transport contracts in the cross-platform core. Put Network.framework and Apple resolver integration behind an Apple-platform adapter guarded by `canImport(Network)`. Keep deterministic resolver/connector fakes in NEWSFLOWCore tests so Linux CI can test policy and orchestration without pretending to exercise Apple's network stack.

Do not replace FeedHTTPClient or remove the existing URLSession implementation until the adapter passes the acceptance tests on Apple Foundation and iOS Simulator. The existing implementation remains subject to the documented DNS limitation.

## References

- Apple: sec_protocol_options_set_tls_server_name — https://developer.apple.com/documentation/security/sec_protocol_options_set_tls_server_name%28_%3A_%3A%29
- Apple: Creating an Identity for Local Network TLS — https://developer.apple.com/documentation/network/creating-an-identity-for-local-network-tls
- Apple: Choosing the right networking API (TN3151) — https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api

## Next implementation step

Run and review CI for the new test target. Then implement the controlled TLS fixture to prove peer address, SNI and standard certificate validation for both success and failure cases. Do not proceed to the production resolver or HTTP implementation until this proof is reliable.
