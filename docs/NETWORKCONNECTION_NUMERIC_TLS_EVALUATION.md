# NetworkConnection numeric endpoint and TLS identity evaluation

**Date:** 2026-11-21  
**Branch:** security/feed-url-hardening  
**Status:** Documentation/API review complete; compile and loopback experiment not run

## Question

Can the iOS 26 Swift `NetworkConnection` API connect to a prevalidated numeric `NWEndpoint.hostPort` while preserving the original feed hostname for TLS SNI and certificate hostname verification?

This is the only potentially useful reason to replace the existing `NWConnection`-based pinned TLS factory: retain explicit numeric destination pinning while gaining the new API's structured-concurrency lifecycle.

## Findings

1. `NetworkConnection` accepts an `NWEndpoint` and a protocol-stack builder. A numeric `hostPort` is therefore a supported endpoint shape at the API surface.
2. Apple's documented Swift `TLS` builder modifiers include `applicationProtocols`, `certificateValidator`, `cipherSuiteGroups`, `cipherSuites`, `earlyDataEnabled`, `localIdentity`, `peerAuthentication`, `ticketsEnabled` and `version`. The reviewed public API surface does not document a TLS server-name/SNI override or a supported way to access the underlying `sec_protocol_options_t`.
3. Apple's guidance for clients connecting by IP is explicit: the server certificate must contain that IP address in the Subject Alternative Name IP Address field. The documented numeric-IP example does not preserve a separate DNS hostname for certificate validation.
4. The lower-level `sec_protocol_options_set_tls_server_name` API is used by the current `NWConnection` factory to set the original DNS name. No equivalent documented modifier was found in the new Swift builder.
5. A custom `certificateValidator` is not a substitute for the missing capability unless the implementation proves the expected SNI and preserves normal system chain and hostname verification. It must not become a trust-all or hostname-check bypass.

## Decision

Do not replace `PinnedTLSConnectionFactory` with `NetworkConnection` for feed transport.

The new API may be suitable for connections that do not require numeric destination pinning with a distinct DNS TLS identity. For this SSRF-hardening design, the existing `NWConnection` factory remains the only verified prototype because it connects to the numeric endpoint and explicitly configures the original hostname for TLS SNI.

This is an API/documentation conclusion, not a compile-time proof that no undocumented or future mechanism exists.

## Verification boundary

- Apple documentation was reviewed on 2026-11-21.
- No iOS 26 compile experiment or loopback TLS test was run for `NetworkConnection` in this work session.
- No production code, tests, project configuration or transport wiring were changed.
- The existing `NWConnection` TLS integration tests and CI results remain the applicable verified proof.
- ADR-008 remains Proposed. The production feed transport remains on URLSession and retains its documented DNS-rebinding/SSRF limitation.

## References

- Apple `NetworkConnection`: https://developer.apple.com/documentation/network/networkconnection
- Apple Swift `TLS` builder: https://developer.apple.com/documentation/network/tls
- Apple `Creating an Identity for Local Network TLS` (numeric-IP clients require an IP SAN): https://developer.apple.com/documentation/network/creating-an-identity-for-local-network-tls
- Apple `sec_protocol_options_set_tls_server_name`: https://developer.apple.com/documentation/security/sec_protocol_options_set_tls_server_name(_:_)
- Apple TN3151, `Choosing the right networking API`: https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api
