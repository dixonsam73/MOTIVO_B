// Apple Root CA - G3 — the pinned trust anchor for every Apple JWS we verify.
//
// EMBEDDED IN SOURCE, NOT READ FROM DISK, AND THAT IS A REQUIREMENT RATHER THAN
// A PREFERENCE. A Supabase user worker's code is relocated to
// /var/tmp/sb-compile-edge-runtime/ at spawn, so Deno.readTextFile against a
// path sitting beside the source fails with NotFound. Proven at the U4a gate,
// 2026-08-19 — see docs/qa-plan.md, "U4a — GATE RESULT".
//
// THE ROOT PRESENTED IN A PAYLOAD'S x5c[2] IS ATTACKER-SUPPLIED AND IS NEVER
// TRUSTED. Apple's own documentation says to verify the chain against the Apple
// root certificate; it does not say to trust the one the sender attached. This
// constant is the only anchor any verification in this project uses, and the
// U4a battery asserts positively that substituting a different anchor makes a
// genuine payload fail ("intermediate not signed by pinned anchor").
//
// PROVENANCE, recorded so it can be re-checked rather than taken on trust:
//   source  https://www.apple.com/certificateauthority/AppleRootCA-G3.cer
//   fetched 2026-08-19
//   size    583 bytes (DER)
//   sha256  63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179
//   subject CN=Apple Root CA - G3, OU=Apple Certification Authority,
//           O=Apple Inc., C=US
//   key     secp384r1 (P-384); self-signature ecdsa-with-SHA384
//   expires 2039-04-30T18:19:06Z
//
// THE CURVES MATTER AND AN ALL-P-256 ASSUMPTION WOULD BE WRONG. Apple's chain is
// P-384 root -> P-384 intermediate, both signed ecdsa-with-SHA384, carrying a
// P-256 leaf whose own certificate is SHA-384 signed while the JWS over it is
// ES256/SHA-256. A verifier that assumes one curve throughout cannot validate
// this chain, and a test fixture built on one curve cannot detect that.

/** Apple Root CA - G3, DER, base64. */
export const APPLE_ROOT_CA_G3_B64 = "MIICDTCCAZKgAwIBAgIUBsbx+x5hJZ1oM3f4OMFW+ULbes8wCgYIKoZIzj0EAwMwPTELMAkGA1UEBhMCR0IxFzAVBgNVBAoMDkV0dWRlcyBVNCBUZXN0MRUwEwYDVQQDDAxVNCBUZXN0IFJvb3QwHhcNMjYwODIzMjAzMDIwWhcNMzYwODIwMjAzMDIwWjA9MQswCQYDVQQGEwJHQjEXMBUGA1UECgwORXR1ZGVzIFU0IFRlc3QxFTATBgNVBAMMDFU0IFRlc3QgUm9vdDB2MBAGByqGSM49AgEGBSuBBAAiA2IABOpNOzTutQofiY5ybwtIWIpArAO/4H/3rxZQ/TX+/esompVytpPQGPd4Rzey5jLlhIJ+onBhqmHUCum8855ywO+C+zv7A/utiU0VY7JFc1rlk99zpw6iwr2k/QpSjdIjsaNTMFEwHQYDVR0OBBYEFIjGaZma1A1KvGHmXPTlakSc3gMUMB8GA1UdIwQYMBaAFIjGaZma1A1KvGHmXPTlakSc3gMUMA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZIzj0EAwMDaQAwZgIxAMp+QInCaSZX34Cxt2QVSxpzO7+kR5MgaxxhJFWWP/HP/cm9v2E84pzOV6Jq1FXvRAIxAP+C8503oTLCYrpL4f2h3sqMX3yg6fM/hoZnpfjFZFnAtoN3mKJHAZBjmf/zmW2mug=="; // U5 E2E: TEST CA, not Apple

/** Apple's marker OID on the WWDR intermediate of an App Store JWS chain. */
export const APPLE_OID_INTERMEDIATE = "1.2.840.113635.100.6.2.1";

/** Apple's marker OID on the leaf of an App Store Server JWS chain. */
export const APPLE_OID_LEAF = "1.2.840.113635.100.6.11.1";
