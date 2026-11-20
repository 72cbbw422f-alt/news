# Feed transport hardening — implementation spike

**Date:** 2026-11-20  
**Status:** Research completed; implementation not yet verified  
**Branch:** security/feed-url-hardening

## Problem

FeedURLSafety validates URL syntax and literal IPs, but the current URLSession transport resolves DNS itself. A hostname that resolves to a private or special-purpose address can therefore bypass the current URL-shape checks. A separate DNS lookup followed by URLSession is not an acceptable fix: the HTTP stack may resolve the hostname again.

## Candidate: Network.framework

Apple's documentation provides two relevant capabilities:

- NWConnection can target an explicit host/port endpoint.
- sec_protocol_options_set_tls_server_name overrides the name derived from that endpoint for TLS SNI and peer-certificate hostname verification.

Prototype direction for HTTPS:

1. Resolve the feed hostname immediately before connection.
2. Validate the complete A and AAAA answer set. Reject the entire set if any address is non-public or special-purpose.
3. Select one validated address and construct a numeric IPv4/IPv6 endpoint. Do not pass the original DNS hostname as the network endpoint.
4. Configure TLS server name to the original URL hostname. Keep normal system trust evaluation enabled; do not replace it with trust-all or chain-only validation.
5. Establish the connection and assert in integration tests that the remote peer is the selected numeric address.
6. Send an HTTP/1.1 request with the original hostname in the Host header. Parse status, headers, content-length and chunked transfer encoding under strict byte/time limits.
7. On redirect, close the current connection and repeat resolution, validation, pinning and TLS setup for the new destination.
8. Propagate task cancellation to the active connection and resolver operation.

This is a prototype direction, not an approved production implementation. Apple's TLS server-name API documentation establishes the override semantics, but does not by itself prove our complete connection, trust-evaluation and HTTP behavior.

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

Keep URL/address policy and transport contracts in the cross-platform core. Put Network.framework and Apple resolver integration behind an Apple-platform adapter guarded by canImport(Network). Keep deterministic resolver/connector fakes in NEWSFLOWCore tests so Linux CI can test policy and orchestration without pretending to exercise Apple's network stack.

Do not replace FeedHTTPClient or remove the existing URLSession implementation until the adapter passes the acceptance tests on Apple Foundation and iOS Simulator. The existing implementation remains subject to the documented DNS limitation.

## References

- Apple: sec_protocol_options_set_tls_server_name — https://developer.apple.com/documentation/security/sec_protocol_options_set_tls_server_name%28_%3A_%3A%29
- Apple: Creating an Identity for Local Network TLS — https://developer.apple.com/documentation/network/creating-an-identity-for-local-network-tls
- Apple: Choosing the right networking API (TN3151) — https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api

## Next implementation step

Build a minimal Apple-platform proof of concept that opens a TLS connection to a controlled test server by numeric IP while setting the original DNS hostname as the TLS server name. Capture the server-side peer address and test both a valid hostname certificate and a hostname mismatch. Only after that succeeds should the work expand to HTTP parsing, DNS resolution and redirects.
