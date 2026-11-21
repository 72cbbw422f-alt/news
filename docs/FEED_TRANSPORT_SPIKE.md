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
- Splitting the work into separate `DNSServiceQueryRecord` requests for A and AAAA does not fix this: Apple documents each query as running indefinitely until its `DNSServiceRef` is deallocated, and its callback exposes the same `MoreComing` batching flag rather than a one-shot end-of-answer-set event. Two independent queries also require a robust way to establish completion for both families, which this API does not provide.

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

## Network.framework connected-peer validation candidate — 2026-11-21

A second candidate was evaluated to avoid depending on a standalone DNS API: create an `NWConnection` using the hostname, wait for readiness, inspect the connected path's remote endpoint, reject non-public destinations, and only then send the HTTP request.

This is attractive because the request would use the same established connection whose peer was inspected. It also naturally avoids a second DNS lookup between validation and the HTTP request, provided the implementation never reconnects or retries using the hostname without repeating the check.

However, it does **not** satisfy the current strict requirement to reject private destinations before connecting:

- For a connection configured with TCP and TLS, Network.framework's ready state is reached after the TLS handshake completes. The TLS ClientHello and server handshake therefore occur before the application can inspect the ready connection's path.
- A TCP-only connection could be inspected at TCP readiness before sending HTTP bytes, but the public Network.framework API does not provide a documented way to upgrade that already-established `NWConnection` in place by adding `NWProtocolTLS` afterward.
- Using BSD sockets to establish TCP, inspect `getpeername`, and then add TLS through Secure Transport is not an acceptable workaround: Apple marks Secure Transport deprecated, states that it is legacy, and explicitly recommends Network.framework instead. Apple also notes Secure Transport does not support TLS 1.3.

The approach could potentially enforce a narrower policy — no HTTP request bytes are sent until the connected peer is checked — but it would still initiate TCP and, for HTTPS, TLS handshakes to a private/special-purpose address. That is a weaker guarantee than the current fail-closed design and must not be adopted silently.

**Decision:** retain this as a documented fallback candidate only. Do not replace the resolver contract, do not change the security acceptance criteria, and do not wire hostname-based `NWConnection` into the feed client until a deliberate architecture decision approves the weaker pre-application-data guarantee and tests prove the actual remote endpoint semantics for hostname endpoints.

References:
- Apple `NWConnection.State.ready`: https://developer.apple.com/documentation/network/nwconnection/state-swift.enum/ready
- Apple TN3151 (ready-state/TLS and networking API guidance): https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api
- Apple `NWPath.remoteEndpoint`: https://developer.apple.com/documentation/network/nwpath/remoteendpoint
- Apple Secure Transport deprecation: https://developer.apple.com/documentation/security/secure-transport
- WWDC18 Network.framework session (ready state includes completed TLS handshake): https://developer.apple.com/videos/play/wwdc2018/715/

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


## DNS-over-HTTPS resolver candidate evaluation — 2026-11-21

DNS-over-HTTPS (DoH, RFC 8484) is the strongest candidate identified so far for obtaining bounded DNS message responses without treating DNS-SD callback batching as completion.

### What DoH solves

- RFC 8484 maps each DNS query/response pair to one HTTP exchange and defines the `application/dns-message` wire format.
- A resolver adapter can issue explicit IN/A and IN/AAAA queries, await each bounded HTTPS response, parse the DNS message, and combine the returned address records for fail-closed policy validation.
- This creates a protocol-level response boundary for each query and supports ordinary task cancellation of the HTTPS operations.
- The returned numeric addresses can then feed the existing `FeedAddressResolutionService` and `PinnedTLSConnectionFactory` path. The feed connection itself must still use numeric IP pinning; DoH does not justify handing the original feed hostname to URLSession.

### What DoH does not solve automatically

- Two separate A and AAAA queries are not an atomic DNS snapshot. Records may change between queries, and recursive resolvers may return cached answers with different remaining TTLs. The implementation must treat the combined set conservatively and never claim authoritative completeness beyond the resolver responses received.
- CNAME processing, answer-section parsing, RCODE handling, truncation/TC behavior, EDNS options, TTLs, DNSSEC validation semantics and malformed/compressed-name handling all require a real bounded DNS wire parser and explicit tests. A successful HTTP 200 alone is not a successful DNS answer.
- The resolver provider receives the feed hostname queries. This is a privacy and third-party dependency decision, not merely a transport implementation detail.
- A DoH endpoint hostname itself needs a safe bootstrap strategy. Resolving that endpoint through the same untrusted resolver path creates a bootstrap loop; hard-coded IPs create maintenance and certificate-validation concerns. Endpoint selection, TLS hostname verification, redirects and failover must be explicit.
- Silent fallback to system DNS or another resolver would make the security behavior unpredictable and is not acceptable.
- DoH may bypass user-selected system DNS, VPN split-DNS, parental/content filters, enterprise DNS policy or local network naming. The app must not assume that this is an acceptable user-visible behavior.

### Apple system DNS settings are not an app-level answer API

Apple documents NetworkExtension DNS settings that can configure system-wide DNS-over-HTTPS or DNS-over-TLS, with the user explicitly enabling the configuration. This is a device DNS configuration mechanism, not a documented per-query API returning a complete A+AAAA RRset to NEWSFLOW with task cancellation. It therefore does not directly satisfy the resolver protocol contract.

### Options and current recommendation

1. **System resolver with numeric destination pinning:** best alignment with user network configuration, but Apple's documented APIs reviewed so far do not provide the required complete dual-stack answer boundary and cancellation semantics. A deliberately weaker policy could validate every address actually returned by a system lookup and connect only to a validated numeric address, but that would change the current whole-answer-set requirement and needs an explicit ADR decision.
2. **Application-managed DoH:** technically feasible as a separate, opt-in resolver mode with a named provider, clear privacy disclosure, fixed endpoint policy, no redirects/fallback, full DNS parser and comprehensive tests. It bypasses system DNS behavior and adds a provider dependency; do not make it the default without product approval.
3. **Network.framework hostname connection followed by peer inspection:** remains a weaker alternative because TLS handshake traffic precedes peer validation; not approved under the current pre-connect requirement.

**Decision for this spike:** Do not implement DoH as the default resolver and do not add a third-party DNS provider silently. The next architecture decision must choose whether NEWSFLOW prioritizes (a) preserving system/VPN DNS behavior with a documented weaker guarantee based on validating every actual returned destination, or (b) an explicit opt-in DoH resolver with provider/privacy implications. Until that decision is made, keep the production URLSession transport unchanged and retain the documented SSRF/DNS-rebinding limitation.

References:
- RFC 8484 — DNS Queries over HTTPS: https://www.rfc-editor.org/rfc/rfc8484
- Apple NetworkExtension DNS Settings: https://developer.apple.com/documentation/networkextension/dns-settings
- Apple NEDNSOverHTTPSSettings: https://developer.apple.com/documentation/networkextension/nednsoverhttpssettings


## DNS-over-HTTPS resolver candidate — 2026-11-21

DNS-over-HTTPS (DoH, RFC 8484) is a viable *protocol-level* candidate for obtaining bounded DNS responses, but it changes the trust and privacy model and does not by itself solve the entire resolver contract.

### What it improves

- RFC 8484 maps each DNS query/response pair to one HTTPS exchange. With the wire format (`application/dns-message`), the client receives a DNS message with explicit message boundaries rather than an open-ended callback stream.
- The client can issue explicit A and AAAA queries and parse each response independently. It can reject truncated, malformed, mismatched-question, non-success RCODE, or incomplete CNAME-chain responses.
- The DNS message can be parsed and validated before any feed-host connection is attempted. The validated numeric address is then passed to the existing pinned TLS connection factory.
- An HTTP request task can be cancelled; the implementation must propagate Swift task cancellation to the underlying request and must not accept a late response after cancellation.

### Important limitations and design requirements

- A and AAAA are separate DNS questions. Even when issued concurrently, they are not an atomic snapshot; records and TTLs can differ between responses. The resolver adapter must define a bounded policy for combining both responses and fail closed if either query fails or is incomplete. It must not quietly treat one successful family as the complete answer set.
- CNAME chains must be handled deliberately. A response's Answer section can contain aliases and terminal records, but the parser must validate owner names, types, classes, bounds, compression pointers and chain termination. If additional lookups are needed, they must remain within the same resolver policy and cancellation/timeout budget.
- HTTP 2xx does not imply DNS success. RFC 8484 permits DNS error RCODEs inside successful HTTP responses; inspect the DNS header and question, not just the HTTP status.
- HTTPS protects the client-to-resolver channel; it does not itself provide DNSSEC validation. DNSSEC validation is independent. The design must explicitly choose between trusting a resolver's validation indication (and its AD-bit semantics) or implementing DNSSEC validation locally. Do not claim DNSSEC merely because DoH uses TLS.
- DoH sends feed hostnames to the selected resolver. This is a third-party disclosure and creates provider availability, filtering, logging/retention, jurisdiction and censorship dependencies. It bypasses the device's configured system resolver, including VPN, parental-control, enterprise and custom-DNS behavior. No public provider should be selected as a silent default.
- The DoH endpoint itself needs a trusted bootstrap path. A fixed, application-controlled HTTPS endpoint with normal system TLS trust is materially different from arbitrary user-supplied resolver URLs, but its hostname still has to be resolved to establish the resolver connection. This bootstrap is not the feed destination and must not be confused with feed-host pinning. Do not disable certificate validation or follow endpoint redirects to arbitrary hosts.
- Use strict response-size, redirect, timeout and content-type limits. Disable automatic redirects or validate every redirect under a separately specified resolver-endpoint policy. Avoid cache behavior that can outlive DNS TTLs; account for both HTTP cache headers and DNS TTLs.
- A maintained DNS wire-format parser is required. Apple's current TN3151 says to use `dns.h`/`dns_util.h` for raw DNS queries outside the system resolver, while noting `dns_util.h` is deprecated and has no direct replacement; packet parsing therefore needs a separately evaluated maintained dependency or carefully scoped implementation.

### Apple platform distinction

Apple's NetworkExtension DNS Settings APIs configure a system-wide encrypted DNS resolver and require the user to enable the configuration. They are not an app-local DNS lookup API for a feed transport. A DNS Proxy provider is a system-wide proxy extension with additional capability and deployment implications, not a lightweight resolver adapter for this feature. These APIs are therefore not selected for the current feed transport spike.

### Current assessment

DoH has a real advantage over DNS-SD here: each HTTP exchange gives a bounded DNS wire message, making response completion observable. It is the strongest candidate evaluated so far for an app-owned resolver adapter. However, it is **not approved for implementation as the default** until the project explicitly accepts the external resolver/privacy tradeoff, selects the provider/bootstrap strategy, settles A+AAAA/CNAME completeness semantics, and selects a maintained parser with tests.

No production code or feed transport was changed as part of this evaluation.

References:
- RFC 8484, DNS Queries over HTTPS: https://www.rfc-editor.org/rfc/rfc8484.html
- Apple TN3151, Choosing the right networking API: https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api
- Apple DNS Settings: https://developer.apple.com/documentation/networkextension/dns-settings
- Apple DNS Proxy provider: https://developer.apple.com/documentation/networkextension/dns-proxy-provider
- Cloudflare DNS wire format documentation (protocol example only, not a provider recommendation): https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/make-api-requests/dns-wireformat/


## System resolver with per-family getaddrinfo — follow-up evaluation — 2026-11-21

Apple's current TN3151 recommends using the system DNS resolver and specifically recommends `getaddrinfo` for BSD-socket applications. Apple's archived hostname-resolution guidance documents an important behavior: a single `getaddrinfo` call can cancel outstanding IPv6 lookup work shortly after receiving a successful IPv4 result. This is why one unconstrained dual-stack call cannot be treated as proof of a complete A+AAAA result set.

A candidate worth a narrowly scoped experiment is two concurrent, family-constrained system resolver calls (`AF_INET` and `AF_INET6`) on dedicated background workers. Each result list would be converted to numeric addresses, validated, and only those numeric addresses would be passed to the pinned connection factory. This preserves the operating system's configured resolver path more closely than application-managed DoH and avoids a second hostname lookup at the feed connection.

Important limitations remain:
- `getaddrinfo` is synchronous. Swift task cancellation cannot interrupt an already-running call. A cancelled caller can be prevented from connecting after the call returns, but the resolver work itself may continue in the background.
- Separate family calls are not an atomic DNS snapshot and do not prove authoritative RRset completeness. They only produce the candidates returned by the system resolver at that time.
- The experiment must verify behavior on supported iOS versions and real network configurations, including VPN/split DNS, IPv4-only, IPv6-only, NXDOMAIN/NODATA, slow or non-responsive family, multiple addresses, and cancellation.
- No hostname may be passed onward to the feed transport. Every candidate that might be used must be parsed and validated as a numeric IP, and the selected peer must be verified against that exact address.
- If any candidate is malformed or non-public, the current strict whole-set policy rejects the destination. Relaxing that policy to validate only the actual numeric endpoint selected for connection is an architecture change and requires an ADR decision; it must not happen implicitly.

**Assessment:** this is the best next system-DNS experiment because it follows Apple's recommended resolver API and may avoid cross-family early cancellation by separating the calls. It does not satisfy the current active-resolver-cancellation contract, so it is not yet an implementation decision. Do not weaken the contract or ship this adapter without tests and an explicit decision.

References:
- Apple TN3151 — Choosing the right networking API: https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api
- Apple archived hostname resolution guidance (including getaddrinfo IPv6 cancellation behavior): https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/NetworkingTopics/Articles/ResolvingDNSHostnames.html
- RFC 8305 — Happy Eyeballs v2: https://www.rfc-editor.org/rfc/rfc8305


## Apple swift-async-dns-resolver package evaluation — 2026-11-21

Evaluated Apple's `apple/swift-async-dns-resolver`, release **0.8.1** (tagged 2026-10-30; Apache-2.0). It supports separate `queryA(name:)` and `queryAAAA(name:)` calls and targets iOS 13+/macOS 10.15+. Its default implementation selects DNS-SD on Darwin and c-ares on non-Darwin platforms; the public API also allows explicitly constructing `CAresDNSResolver`.

The source-level review found important limitations:

- The Darwin DNS-SD implementation still uses `DNSServiceQueryRecord`, calls `DNSServiceProcessResult` once, then deallocates the service reference. This does not establish a documented complete multi-response A or AAAA answer set. It therefore does not resolve the DNS-SD completion concern recorded above.
- The c-ares implementation has per-query cancellation tests and promptly resumes the awaiting task with `CancellationError`. However, its cancellation handler deliberately does **not** call `ares_cancel`, because that would cancel all requests sharing the channel and can deadlock against the poll loop. The underlying DNS request is left running until its callback or configured timeout, and its resources are released only when that callback arrives. This is caller cancellation, not active cancellation of the resolver operation.
- The library exposes parsed A and AAAA records, but its high-level API performs separate queries. The adapter still needs a fail-closed policy for both families, empty results, CNAME behavior and inconsistent snapshots.
- The package compiles bundled c-ares source and is Apache-2.0 licensed. Its dependency footprint and behavior on the exact iOS deployment target still need a project-level build and device/simulator check before any adoption.

**Assessment:** promising source and API quality, but not a drop-in solution for ADR-008. The default Darwin backend does not provide the missing completion guarantee, while the c-ares backend does not stop the underlying DNS operation on cancellation. Do not integrate it as the production resolver under the current strict acceptance criteria. It remains a candidate only if the cancellation requirement is explicitly refined to mean prompt caller cancellation with bounded background resolver cleanup, and if A/AAAA completion and CNAME semantics are independently demonstrated.

References:
- Apple Swift Async DNS Resolver repository: https://github.com/apple/swift-async-dns-resolver
- Release 0.8.1: https://github.com/apple/swift-async-dns-resolver/releases/tag/0.8.1
- Darwin implementation: https://github.com/apple/swift-async-dns-resolver/blob/0.8.1/Sources/AsyncDNSResolver/dnssd/DNSResolver_dnssd.swift
- c-ares implementation: https://github.com/apple/swift-async-dns-resolver/blob/0.8.1/Sources/AsyncDNSResolver/c-ares/DNSResolver_c-ares.swift
- Per-query cancellation tests: https://github.com/apple/swift-async-dns-resolver/blob/0.8.1/Tests/AsyncDNSResolverTests/c-ares/CAresCancellationTests.swift


## Follow-up: upstream c-ares backend readiness risk — 2026-11-21

The Apple `swift-async-dns-resolver` repository's latest release remains 0.8.1 (2026-10-30). A current upstream pull request, [#93 — Only report sockets to c-ares when the OS says they are ready](https://github.com/apple/swift-async-dns-resolver/pull/93), is still open.

The proposed fix describes a Darwin TCP readiness defect in the package's c-ares `QueryProcessor`: the current polling loop forwards sockets that c-ares is interested in to `ares_process_fd` every 10 ms without first checking OS-level readiness. On macOS, a TCP connection still in SYN_SENT can consequently be treated as connected; a send then fails with ENOTCONN and is surfaced as a spurious connection-refused error. The report says this can affect forced TCP queries and the TCP fallback after truncated UDP responses. The PR includes readiness polling and additional tests, but it is not part of the latest 0.8.1 release and must not be assumed available in a pinned dependency.

This is an additional adoption risk beyond the already documented cancellation and DNS-SD completion limitations:
- The default Darwin backend still does not establish a complete A/AAAA answer boundary.
- The c-ares backend promptly cancels the Swift caller but intentionally leaves the underlying query running until callback/timeout.
- The current released c-ares polling implementation has an unresolved reported TCP readiness issue on macOS.
- The upstream readiness fix has not yet been merged/released as of this review.

**Assessment:** do not add `swift-async-dns-resolver` 0.8.1 to NEWSFLOW at this stage. Re-evaluate only after the upstream readiness fix is merged and released, then run the package's own tests and NEWSFLOW integration tests on the exact iOS Simulator/Xcode toolchain. Even after that, cancellation semantics and complete-answer/CNAME handling remain separate acceptance gates.

References:
- Latest release: https://github.com/apple/swift-async-dns-resolver/releases/latest
- Upstream PR #93: https://github.com/apple/swift-async-dns-resolver/pull/93
- c-ares backend implementation at 0.8.1: https://github.com/apple/swift-async-dns-resolver/blob/0.8.1/Sources/AsyncDNSResolver/c-ares/DNSResolver_c-ares.swift


## Follow-up: c-ares cancellation and system resolver trade-off — 2026-11-21

A deeper source review of Apple `swift-async-dns-resolver` 0.8.1 confirms the cancellation boundary:

- `CAresDNSResolver` uses one shared c-ares channel and a polling task. `AresChannel.withChannel` serializes calls into c-ares with an `NSLock`.
- Its task cancellation handler calls `QueryReplyHandler.cancel()`, which resumes the Swift continuation with `CancellationError`; it intentionally does not call `ares_cancel`.
- The source explicitly states that the c-ares request remains active until its callback or configured timeout. The callback later releases its per-query context.
- The package's own cancellation tests verify prompt caller cancellation, isolation between parallel queries, and eventual cleanup after timeout. They do not prove immediate cancellation of the DNS network request.
- Calling `ares_cancel` from the current cancellation handler is not a safe patch: the package maintainers explicitly document lock/poll-loop deadlock and cross-query cancellation concerns. A fork would need a redesigned serialized event-loop/cancellation model, not a one-line call.

A dedicated c-ares channel per DNS operation could avoid cross-query cancellation of unrelated requests, but it does **not** by itself solve the poll-loop synchronization/deadlock issue. This is a research direction, not an approved implementation.

### System getaddrinfo: security guarantee versus complete RRset

Apple's archived iOS networking guidance states that `getaddrinfo` is synchronous and that its implementation may cancel outstanding IPv6 lookup work shortly after receiving a successful IPv4 answer. Therefore it cannot be treated as a complete A+AAAA RRset API. Apple's current TN3151 recommends using the system resolver and warns that manually resolving then connecting is generally an anti-pattern because it complicates VPN On Demand and Happy Eyeballs.

There is nevertheless a distinct security model worth evaluating: accept only the numeric addresses actually returned by the system resolver, validate **every returned candidate**, and connect only to a selected validated numeric endpoint with the existing pinned TLS factory. Under this model, an address omitted by the system resolver is never used as a destination; DNS rebinding cannot change the already selected numeric endpoint. This can provide a meaningful SSRF destination guarantee without claiming a complete DNS RRset. It does not satisfy the current stricter ADR requirement to reject a hostname if any unreturned record in its full A/AAAA RRset is non-public.

Remaining caveats before even a prototype:
- `getaddrinfo` is synchronous and has no per-request cancellation API; dispatching it off the caller task only cancels the wait, not the resolver work.
- Apple explicitly warns that resolution-then-connect can interfere with VPN On Demand and requires a correct Happy Eyeballs strategy. A pinned-IP client would need its own address racing/fallback behavior and must preserve the relevant system network semantics.
- NAT64/DNS64 and interface-specific address synthesis must be tested; do not classify synthesized IPv6 endpoints as ordinary public IPv6 without understanding the translation path.
- The implementation must validate all candidates returned by the resolver and must never fall back to the original hostname in URLSession or NWConnection.
- This is a proposed change to the security contract, not an implementation detail. It requires an explicit ADR decision before code.

### Updated decision framing

There are now three materially different choices:
1. **Strict full RRset + active cancellation:** DoH or a purpose-built resolver/event-loop implementation. Strongest policy, higher privacy and maintenance cost.
2. **System resolver + validate every returned numeric candidate:** preserves system resolver choice better, but relaxes full-RRset completeness and has synchronous/non-cancellable resolution plus VPN/Happy-Eyeballs concerns.
3. **Apple DNS-SD / current async wrapper:** not accepted because completion is not reliable for the complete answer set.

No code or production transport was changed during this follow-up.

References:
- Apple archived iOS DNS resolution guidance: https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/NetworkingTopics/Articles/ResolvingDNSHostnames.html
- Apple TN3151: https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api
- Apple swift-async-dns-resolver 0.8.1 c-ares channel: https://github.com/apple/swift-async-dns-resolver/blob/0.8.1/Sources/AsyncDNSResolver/c-ares/AresChannel.swift
- Apple swift-async-dns-resolver 0.8.1 cancellation implementation: https://github.com/apple/swift-async-dns-resolver/blob/0.8.1/Sources/AsyncDNSResolver/c-ares/DNSResolver_c-ares.swift
- Apple swift-async-dns-resolver 0.8.1 cancellation tests: https://github.com/apple/swift-async-dns-resolver/blob/0.8.1/Tests/AsyncDNSResolverTests/c-ares/CAresCancellationTests.swift
