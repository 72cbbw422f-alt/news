# Feed transport hardening — implementation spike

**Date:** 2026-11-20  
**Status:** TLS integration harness, IP address policy, Core resolver orchestration and cancellation tests verified in CI; Apple DNS adapter remains blocked on a safe complete-answer API (2026-11-21)  
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

The iOS workflow runs the simulator build and unit-test scheme on an available iPhone Simulator. The loopback TLS integration suite is verified in CI (8 iOS tests total, 0 failures on the current branch head).

## Verified proof: controlled TLS server

The controlled TLS server/client integration fixture is implemented and has passed on iOS Simulator. It establishes the following:

1. The client connects to the selected numeric IPv4/IPv6 endpoint without a second hostname lookup.
2. The server observes the expected peer address.
3. The ClientHello carries the original DNS hostname as SNI.
4. A certificate valid for that hostname succeeds under normal system trust evaluation.
5. A hostname mismatch fails.
6. An untrusted chain fails.
7. Cancellation and timeout terminate the connection and complete the test exactly once.

The certificate strategy must preserve normal trust evaluation. Do not make a test pass by adding a trust-all callback or disabling hostname verification. If a private test CA is used, isolate its trust configuration to the test environment and retain normal chain and hostname checks.

The local `NWListener` fixture uses a test-only CA and identity. Trust evaluation and hostname policy remain enabled; the production factory has no test trust callback.

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

The cross-platform, injectable resolver contract and fail-closed orchestration now exist in NEWSFLOWCore:
- `FeedAddressResolving` requires the resolver to return the complete A/AAAA answer set and cooperate with task cancellation.
- `FeedAddressResolutionService` validates the hostname, checks cancellation before and after resolution, and rejects the entire answer set unless every address passes `FeedIPAddressPolicy`.
- Deterministic fake-resolver tests cover valid dual-stack answers, invalid hostnames, mixed public/private answers, empty and malformed answers, resolver failures and cancellation while the resolver is suspended.

The next step is **not** to implement a speculative adapter. First establish an Apple-supported resolver API that provides a reliable completion boundary for the complete initial A and AAAA answer set and can be actively cancelled. Then prove the returned numeric IP is passed to `PinnedTLSConnectionFactory` without hostname re-resolution. Keep the production feed transport unchanged until DNS, TLS, redirects, bounded HTTP framing, timeout and cancellation acceptance tests are all covered.

## Apple resolver API evaluation — 2026-11-21

The initial candidate, `DNSServiceGetAddrInfo`, is asynchronous and supports IPv4, IPv6 or both. Its semantics do not currently satisfy the security requirement for a complete one-shot answer set:

- Apple documents that the query remains active until the caller deallocates its `DNSServiceRef`.
- `kDNSServiceFlagsMoreComing` only indicates that another result is already queued. When it is absent, no more results are queued *at that instant*; additional answers can arrive later. It is not a completion signal for both address families.
- `kDNSServiceFlagsTimeout` stops the query after a system-determined interval and delivers `kDNSServiceErr_Timeout`, even if answers arrived earlier. That timeout callback cannot safely be treated as successful completion.
- `DNSServiceRefDeallocate` does provide a cancellation mechanism, but cancellation alone does not solve the missing completion boundary.

The alternative `CFHost` APIs expose asynchronous resolution and cancellation, but Apple's current documentation marks the CFHost API family deprecated. The POSIX `getaddrinfo` API is synchronous; Apple's archived guidance also notes that it may cancel outstanding IPv6 work shortly after receiving an IPv4 answer, so it cannot be assumed to return the complete A+AAAA set required here.

**Decision for this spike:** do not ship a DNS-SD implementation that treats a quiet callback interval or `MoreComing == false` as completion. Do not use `CFHost` or a single `getaddrinfo` call as a substitute without resolving their documented limitations. Continue evaluating supported approaches; if no system API can meet the complete-answer and cancellation contract, revisit the transport/security architecture explicitly rather than weakening the requirement silently.

References:
- Apple `DNSServiceGetAddrInfo`: https://developer.apple.com/documentation/dnssd/dnsservicegetaddrinfo%28_%3A_%3A_%3A_%3A_%3A_%3A_%3A%29
- Apple `kDNSServiceFlagsMoreComing`: https://developer.apple.com/documentation/dnssd/kdnsserviceflagsmorecoming
- Apple `kDNSServiceFlagsTimeout`: https://developer.apple.com/documentation/dnssd/kdnsserviceflagstimeout
- Apple `DNSServiceRefDeallocate`: https://developer.apple.com/documentation/dnssd/dnsservicerefdeallocate%28_%3A%29
- Apple `CFHost` deprecation status: https://developer.apple.com/documentation/cfnetwork/cfhost
- Apple TN3151 networking guidance: https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api
- Apple archived hostname resolution guidance: https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/NetworkingTopics/Articles/ResolvingDNSHostnames.html

## Verified resolver orchestration and cancellation — 2026-11-21

Commit `6acb11359342139ed1bd6d17cc403c5f911fad12` adds `testPropagatesCancellationWhileResolverIsSuspended` to `NEWSFLOWCore/Tests/NEWSFLOWCoreTests/FeedAddressResolutionTests.swift`. The test waits until the fake resolver has actually started, cancels the in-flight task, and verifies that cancellation reaches the awaiting caller as `CancellationError`.

The commit passed the push CI workflows:
- NEWSFLOW Core Tests: Linux and Apple Foundation jobs passed.
- NEWSFLOW iOS Build: simulator build and XCTest job passed.
- The corresponding pull-request Core jobs also passed. The pull-request iOS job was still running at the time of this documentation update; the successful push iOS run covers the same commit.

This verifies the Core orchestration contract against a cancellation-aware fake. It does **not** verify a production Apple DNS resolver or prove that an OS resolver operation is cancelled. The production feed transport remains on URLSession and unchanged.


## Certificate fixture diagnosis and correction — 2026-11-20

The trust diagnostics from run `44818509219` identified the root cause: the test leaf certificate exceeded Apple's maximum temporal validity period. The Security framework returned OSStatus `-67901` with the explicit detail `Certificate exceeds maximum temporal validity period`. This was a test-fixture defect, not evidence that production trust evaluation should be relaxed.

Regenerated the test-only CA and server identity:
- Root CA: 2026-11-20 through 2036-11-17.
- Server certificate: 2026-11-20 through 2027-11-20 (365 days).
- SAN remains `DNS:feeds.example.org`.
- PKCS#12 passphrase remains test-only.

Fixture files updated:
- `NEWSFLOWAppTests/Fixtures/ca.pem`
- `NEWSFLOWAppTests/Fixtures/server.p12.base64`

The renewed fixture was subsequently verified by the passing iOS Simulator integration suite documented below.

## CI result — 2026-11-20 (commit `3d5b3572070b8fb9be561c8e92d4887fa9b814f0`)

- `NEWSFLOW Core Tests` run `44814680729`: passed on Linux and Apple Foundation.
- `NEWSFLOW iOS Build` run `44814680722`: simulator app build passed; `Run iOS unit tests` failed.
- The integration suite executed 3 tests and reported 9 failures (2 unexpected). The trusted-hostname handshake did not reach `.ready`; the untrusted-chain case also timed out waiting for the client state callback. Simulator logs include BoringSSL `CERTIFICATE_VERIFY_FAILED` / `certificate unknown` alerts.
- The current test harness therefore does **not** prove SNI, pinned remote endpoint, hostname validation or untrusted-chain rejection. The cancellation assertion also cannot be treated as an overall passing suite while the suite is red.
- The exact trust-evaluation failure is not yet diagnosed: the callback currently discards the `CFError` from `SecTrustEvaluateWithError`, and the test does not record the individual `SecTrustSetAnchorCertificates`, `SecTrustSetAnchorCertificatesOnly` and policy results. Add test-only diagnostics before changing certificate/trust behavior.
- Do not weaken trust evaluation, disable hostname validation, or change the production factory. Production feed transport remains on URLSession and unchanged.

Next step: instrument the DEBUG-only test trust callback to record anchor/policy status and the `SecTrustEvaluateWithError` failure reason, then rerun the iOS simulator tests. Do not proceed to IPv6/DNS implementation until the controlled TLS handshake passes.

## Verified TLS milestone — 2026-11-21

Commit `16df70dc9fe3deb1ec43197ee6a211f902917432` passed all CI jobs:
- Core Tests on Linux: passed (27 tests).
- Core Tests on Apple Foundation: passed.
- iOS Simulator build and tests: passed (8 tests total).
- TLS integration tests: 3 passed, 0 failures. The suite verifies trusted-hostname success, hostname mismatch rejection, untrusted-chain rejection, SNI on the successful handshake, numeric loopback remote endpoint and cancellation.

The test harness now treats Network.framework's `.waiting(error)` state as an observable TLS rejection in the negative handshake cases. This is test-harness behavior only; production TLS trust configuration was not changed.

## IP address policy implementation — 2026-11-21

Added `NEWSFLOWCore/Sources/NEWSFLOWCore/FeedIPAddress.swift`:
- Parses numeric IPv4 and IPv6 literals using the platform C networking parser.
- Exposes a conservative `isPublicUnicast` classification.
- Rejects private, loopback, link-local, shared, multicast, documentation, reserved and selected transition/special-purpose ranges.
- Adds `FeedIPAddressPolicy.validateAnswerSet`, which rejects an empty set, malformed addresses or the entire set when any member is non-public. It never filters unsafe answers and continues with a subset.

Added `NEWSFLOWCore/Tests/NEWSFLOWCoreTests/FeedIPAddressTests.swift` to cover accepted public IPv4/IPv6 addresses, special-purpose ranges, malformed literals and mixed public/private answer sets.

This is address-policy groundwork only. No DNS resolver, DNS cancellation, numeric-IP connection orchestration, redirect re-resolution or production transport integration has been implemented. The new policy must pass Linux and Apple Foundation CI before it is considered verified.


## Verified IP policy CI milestone — 2026-11-21 (commit `62c827decd994063cf9cfe49c56998caef5fd07a`)

The current branch head passed all relevant CI jobs:
- iOS Simulator build and XCTest: 8 tests, 0 failures. This includes 5 pinned TLS factory tests and 3 loopback TLS integration tests.
- NEWSFLOWCore on Linux: 33 tests, 0 failures.
- NEWSFLOWCore with Apple Foundation: 35 tests, 0 failures.
- The six new `FeedIPAddressTests` passed on both Core platforms.

The policy implementation is now CI-verified, but it remains a policy primitive rather than a resolver. No DNS query, cancellation-aware resolution, endpoint orchestration, redirect re-resolution or production transport integration exists yet. The IPv4/IPv6 classification remains intentionally conservative and must be reviewed against the current IANA special-purpose registries before production use; it should not be described as a complete registry-derived policy.

Current verified head: `62c827decd994063cf9cfe49c56998caef5fd07a`. PR #2 remains open and Draft; no merge and no IPA build have occurred.
