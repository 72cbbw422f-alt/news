# Engineering quality checklist

## Every change
- [ ] Compiles with the declared Swift toolchain.
- [ ] Unit tests cover success, edge cases and failure cases.
- [ ] No force unwraps on feed/network input.
- [ ] No unbounded network response or parser work.
- [ ] No secrets or personal data in source/logs.
- [ ] Loading, empty, offline and error states considered.
- [ ] VoiceOver labels and Dynamic Type checked for UI changes.
- [ ] Documentation and changelog updated when behavior changes.

## Feed parser fixtures
- [ ] RSS 2.0 with common fields.
- [ ] RSS with CDATA and HTML entities.
- [ ] Atom with alternate links and updated timestamps.
- [ ] Missing dates, missing IDs and relative links.
- [ ] Invalid XML and truncated documents.
- [ ] Duplicate items and changed item metadata.
- [ ] Large feed rejected at configured limits.
- [ ] Private, loopback, link-local, shared, multicast and reserved IPv4 destinations rejected, including hexadecimal and legacy numeric host forms.
- [ ] IPv6 literals, including IPv4-mapped IPv6 loopback forms, are rejected.
- [ ] Local hostnames, embedded credentials, unsupported schemes and non-standard ports rejected.
- [ ] Redirect destinations pass the same URL safety validation.
- [ ] An HTTP-level redirect to a loopback/private destination is rejected before the redirected request is issued.
- [ ] DNS resolution/address pinning limitations explicitly tracked.

## Release candidate
- [ ] Clean build on supported Xcode.
- [ ] Unit tests pass.
- [ ] Install and launch on physical iPhone.
- [ ] Refresh with slow, offline and malformed feeds.
- [ ] Persistence verified across relaunch.
- [ ] VoiceOver, Dynamic Type, light/dark mode checked.
- [ ] App signing and installation method documented.