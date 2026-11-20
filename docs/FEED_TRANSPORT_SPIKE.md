# Feed transport hardening — implementation spike

**Date:** 2026-11-20  
**Status:** TLS integration harness present; iOS simulator verification failing (2026-11-20)  
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

The integration suite in `NEWSFLOWAppTests/PinnedTLSTransportIntegrationTests.swift` adds a local `NWListener` TLS server and tests:

- Successful connection to the numeric loopback endpoint while sending the original DNS name as SNI.
- The connected path's effective remote endpoint is the expected loopback IP.
- A valid hostname succeeds and a hostname mismatch fails.
- An untrusted certificate chain fails.
- Connection cancellation reaches the cancelled state.

The test fixture uses a dedicated test-only CA and PKCS#12 server identity. The client trust callback is exposed only through a `#if DEBUG` factory entry point and performs `SecTrustEvaluateWithError` with an isolated anchor and SSL hostname policy. The production factory has no configurable trust callback and retains default system trust evaluation. The fixture private key is not a production credential and must never be reused outside tests.

The SNI assertion is made on the successful handshake. A hostname-mismatch handshake is expected to abort before the server reaches ready state, so it is not used as the SNI observation case.

The iOS workflow runs the simulator build and unit-test scheme on an available iPhone Simulator. The new integration tests are not considered verified until that CI run passes.

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

Run and review CI for the new loopback TLS integration tests. If they pass, extend the proof to IPv6 and cancellation/timeout edge cases, then begin the resolver and complete A/AAAA address policy. Keep the production feed transport unchanged until DNS, TLS and bounded HTTP behavior are all covered.


## CI result — 2026-11-20 (commit `3d5b3572070b8fb9be561c8e92d4887fa9b814f0`)

- `NEWSFLOW Core Tests` run `44814680729`: passed on Linux and Apple Foundation.
- `NEWSFLOW iOS Build` run `44814680722`: simulator app build passed; `Run iOS unit tests` failed.
- The integration suite executed 3 tests and reported 9 failures (2 unexpected). The trusted-hostname handshake did not reach `.ready`; the untrusted-chain case also timed out waiting for the client state callback. Simulator logs include BoringSSL `CERTIFICATE_VERIFY_FAILED` / `certificate unknown` alerts.
- The current test harness therefore does **not** prove SNI, pinned remote endpoint, hostname validation or untrusted-chain rejection. The cancellation assertion also cannot be treated as an overall passing suite while the suite is red.
- The exact trust-evaluation failure is not yet diagnosed: the callback currently discards the `CFError` from `SecTrustEvaluateWithError`, and the test does not record the individual `SecTrustSetAnchorCertificates`, `SecTrustSetAnchorCertificatesOnly` and policy results. Add test-only diagnostics before changing certificate/trust behavior.
- Do not weaken trust evaluation, disable hostname validation, or change the production factory. Production feed transport remains on URLSession and unchanged.

Next step: instrument the DEBUG-only test trust callback to record anchor/policy status and the `SecTrustEvaluateWithError` failure reason, then rerun the iOS simulator tests. Do not proceed to IPv6/DNS implementation until the controlled TLS handshake passes.