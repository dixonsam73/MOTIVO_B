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
export const APPLE_ROOT_CA_G3_B64 = "MIICCzCCAZKgAwIBAgIUB0dj4SKp34dECXhYW8K1tmNl+vMwCgYIKoZIzj0EAwMwPTELMAkGA1UEBhMCR0IxFzAVBgNVBAoMDkV0dWRlcyBVNCBUZXN0MRUwEwYDVQQDDAxVNCBUZXN0IFJvb3QwHhcNMjYwOTAzMDg1NzQ1WhcNMzYwODMxMDg1NzQ1WjA9MQswCQYDVQQGEwJHQjEXMBUGA1UECgwORXR1ZGVzIFU0IFRlc3QxFTATBgNVBAMMDFU0IFRlc3QgUm9vdDB2MBAGByqGSM49AgEGBSuBBAAiA2IABONE9ZpKjKWHbvH+Ambe1W6qDawpGJcVWG0xP8ThmmR28NWWjR+wMhJKhryJ2bkQWBo1Obnd1+DxiPa16n7rgE+UrICMDKM0cchhbphP0ZI2RfnSgF7u46t2gNt4pEgsoKNTMFEwHQYDVR0OBBYEFPR20+MLBoTVOD1BXZTUW9bbYjMVMB8GA1UdIwQYMBaAFPR20+MLBoTVOD1BXZTUW9bbYjMVMA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZIzj0EAwMDZwAwZAIwKnhgtrjSpXLdKk39fmFE1EMsEmpjzdu6esPdHz6M7kzGxM88Buq0Ee4VFOyiPI9eAjBSlo45RcgsjoiWWx8FxM9ZWMl08TaYpW2Lrjc+KJInmcFjyXHytC9Qb/zEnm2rW30="; // U5 E2E: TEST CA, not Apple

/** Apple's marker OID on the WWDR intermediate of an App Store JWS chain. */
export const APPLE_OID_INTERMEDIATE = "1.2.840.113635.100.6.2.1";

/** Apple's marker OID on the leaf of an App Store Server JWS chain. */
export const APPLE_OID_LEAF = "1.2.840.113635.100.6.11.1";
