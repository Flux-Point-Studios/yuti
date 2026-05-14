# Security policy

## Reporting a vulnerability

If you believe you've found a security issue in Yuti, please report it privately. **Do not file a public GitHub issue.**

- Email: security@fluxpointstudios.com
- PGP key: available on request
- Response SLA: we acknowledge reports within 72 hours and provide a triage outcome within 7 days

Please include in your report:

1. A description of the issue and its potential impact
2. Reproduction steps (a minimal test case if possible)
3. Affected version / commit hash / platform (iOS / Android / PWA)
4. Whether the vulnerability has been disclosed elsewhere

We will work with you in good faith on a disclosure timeline. Reports that follow [coordinated disclosure](https://www.iso.org/standard/72311.html) best practices and give us a reasonable patch window will be credited (with your consent) in release notes.

## Scope

In scope:

- The Yuti mobile app (iOS / Android)
- The Yuti PWA at bluelight-alpha.vercel.app and successor domains
- Any signing or key-handling code path
- The CIP-30-DeepLink reference implementation (URL handler, payload decrypt, session-binding signature)

Out of scope:

- Vulnerabilities in third-party libraries that have not been adapted by Yuti (please report those upstream)
- Issues that require physical access to an unlocked device
- Social-engineering attacks
- Findings that depend on a user accepting an obviously suspicious prompt

## CIP-30-DeepLink

Yuti is the reference wallet-side implementation for [CIP-30-DeepLink](https://github.com/cardano-foundation/CIPs/pull/1189). Vulnerabilities in the deep-link protocol shape itself (rather than Yuti's implementation of it) should also be reported on that PR thread so other wallet implementors are aware.

## Public key

A `/.well-known/security.txt` will be published alongside this policy in a future release.
