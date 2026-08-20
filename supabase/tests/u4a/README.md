# U4a — the ASSN V2 verification route gate

**Local and disposable only.** Every container here is throwaway, is never given
a credential, and nothing in this directory can reach production.

## What it answers

*Can the Supabase Edge Runtime verify an App Store Server Notifications V2
payload — an ES256 JWS carrying an x5c certificate chain — against a pinned
Apple Root CA G3?*

B-28 said there was no proven route. There is now, and two obvious ones are
dead. **The gate is re-runnable rather than a recorded historical result**,
because "the official library does not work here" is a claim with a shelf life.

```bash
./supabase/tests/u4a/run.sh
```

## Why it runs in a container rather than under `deno`

There is no `deno` on this machine, and a result from some other JavaScript
runtime would answer a different question. The probe runs inside the real
`public.ecr.aws/supabase/edge-runtime` image. The original gate obtained every
result **twice** — as the main service and inside a spawned user worker — and
the two agreed exactly, so nothing rests on a privilege the shipping context
lacks.

## Why the probe is not a function under `supabase/functions/`

Adding one there would make it deployable, and **`supabase functions deploy` is
not scoped to the function you name** — deploying `c44_exchange_probe` once
re-versioned `delete_account_v1` as a side effect. A test that could ship is not
a test worth having.

## What it exercises

**The shipping module, not a reimplementation.** `probe.ts` imports
`_shared/appstore/jws.ts` — the same file `appstore_notifications_v1` imports —
so this doubles as a regression gate.

| | |
|---|---|
| **Route `node:crypto`** | Asserted **dead**. The class exists and a naive probe reports `hasX509: true`; `.verify` and `.toString` both throw `ERR_NOT_IMPLEMENTED`. **Capability presence is not capability** |
| **Route `@apple/app-store-server-library`** | Asserted **broken here**. It imports cleanly and rejects a payload it should accept, reporting `VERIFICATION_FAILURE` — **the same status it reports for a genuine forgery** |
| **Route `@peculiar/x509` + Web Crypto** | The adopted route. Good payload, both nested JWS, and ten negatives |
| **Pinning** | A good payload verified against the *real* Apple anchor must FAIL. This is the assertion that proves `x5c[2]` is ignored |
| **The real Apple link** | Genuine WWDR G6 against the genuine, **committed** Apple Root CA G3 — P-384/SHA-384 |

## The fixture mirrors Apple's real shape, and that is not pedantry

Apple's chain is a **P-384 root and P-384 intermediate, both `ecdsa-with-SHA384`,
carrying a P-256 leaf** whose own certificate is SHA-384 signed while the JWS
over it is ES256/SHA-256. An all-P-256 test chain verifies happily and proves
nothing about the link that carries Apple's trust.

**Both Apple marker OIDs are present, and adding them changed a result.**
Without `1.2.840.113635.100.6.2.1` on the intermediate and
`1.2.840.113635.100.6.11.1` on the leaf, the official library rejects a good
fixture *correctly* — indistinguishable from rejecting it wrongly. The first
reading of that route was therefore not reportable.

## What it does NOT prove

**No genuine Apple-signed ASSN payload has been verified.** None can be
legitimately obtained without a deployed endpoint. Root→intermediate is proven
against Apple's own certificates; **intermediate→leaf and the JWS signature are
proven only against a faithful synthetic chain.** The first genuine Apple-signed
payload obtainable is Apple's own test notification at U4i, and **that is where
B-28's remaining half discharges.**

## Secrets

**None.** The only Apple artefacts touched are public certificate-authority
certificates. The test CA keys are generated fresh on every run into `.work/`,
which is gitignored — a committed private key is a committed private key
whatever it protects.
