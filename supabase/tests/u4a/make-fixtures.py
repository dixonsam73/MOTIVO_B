#!/usr/bin/env python3
"""U4a / U4 JWS fixture generator. LOCAL AND DISPOSABLE ONLY.

Builds a certificate chain that MIRRORS APPLE'S REAL SHAPE, plus a signed
notification and every negative case the batteries need.

WHY THE SHAPE MATTERS, and it is not pedantry. Apple's real chain is a P-384
root and a P-384 intermediate, both signed ecdsa-with-SHA384, carrying a P-256
leaf whose own certificate is SHA-384 signed while the JWS over it is
ES256/SHA-256. An all-P-256 test chain verifies happily and proves NOTHING about
the link that actually carries Apple's trust. This generator reproduces the real
curves and both of Apple's marker OIDs.

ADDING THE MARKER OIDs CHANGED A GATE RESULT. Without
1.2.840.113635.100.6.2.1 on the intermediate and 1.2.840.113635.100.6.11.1 on
the leaf, the official Apple library rejects a good fixture CORRECTLY — which is
indistinguishable from rejecting it wrongly, and the first U4a reading was
therefore not reportable.

NO PRIVATE APPLE MATERIAL IS INVOLVED AND NONE IS EVER WRITTEN HERE. The keys
below are generated fresh on every run and are meaningless outside this
directory. The only Apple artefacts touched are PUBLIC certificate-authority
certificates.

Outputs to ./.work/ , which is gitignored. Nothing generated is committed.
"""

import base64
import json
import os
import pathlib
import re
import subprocess
import sys
import time
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
WORK = HERE / ".work"
REPO = HERE.parents[2]
ANCHOR_TS = REPO / "supabase/functions/_shared/appstore/apple_root_ca_g3.ts"

APPLE_WWDR_G6_URL = "https://www.apple.com/certificateauthority/AppleWWDRCAG6.cer"
OID_INTERMEDIATE = "1.2.840.113635.100.6.2.1"
OID_LEAF = "1.2.840.113635.100.6.11.1"


def sh(*args, **kw):
    return subprocess.run(args, check=True, capture_output=True, **kw)


def b64u(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).decode().rstrip("=")


def der_to_raw(der: bytes, n: int) -> bytes:
    """DER SEQUENCE{INTEGER r, INTEGER s} -> raw r||s.

    Web Crypto and JWS both want raw r||s, never DER — the TN3107 lesson already
    learned by revoke_apple_identity_v1. openssl emits DER, so this converts.
    """
    assert der[0] == 0x30
    i = 2 + ((der[1] & 0x7F) if der[1] & 0x80 else 0)
    out = b""
    for _ in range(2):
        assert der[i] == 0x02
        ln = der[i + 1]
        v = der[i + 2 : i + 2 + ln]
        i += 2 + ln
        out += v.lstrip(b"\x00").rjust(n, b"\x00")
    return out


def anchor_b64_from_source() -> str:
    """Read the PINNED anchor out of the committed production constant.

    Deliberately NOT a fresh download: this makes the harness prove that the
    certificate the shipping code pins is the real Apple Root CA G3, rather than
    testing some other copy of it.
    """
    text = ANCHOR_TS.read_text()
    body = text.split("APPLE_ROOT_CA_G3_B64 =", 1)[1].split(";", 1)[0]
    return "".join(re.findall(r'"([^"]*)"', body))


def main() -> int:
    WORK.mkdir(exist_ok=True)
    os.chdir(WORK)

    # ---- chain mirroring Apple: P-384 root -> P-384 intermediate -> P-256 leaf
    sh("openssl", "ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", "root.key")
    sh("openssl", "req", "-x509", "-new", "-key", "root.key", "-sha384", "-days", "3650",
       "-subj", "/C=GB/O=Etudes U4 Test/CN=U4 Test Root", "-out", "root.pem")

    sh("openssl", "ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", "inter.key")
    sh("openssl", "req", "-new", "-key", "inter.key",
       "-subj", "/C=GB/O=Etudes U4 Test/CN=U4 Test Intermediate", "-out", "inter.csr")
    pathlib.Path("inter.ext").write_text(
        "basicConstraints=critical,CA:TRUE,pathlen:0\n"
        "keyUsage=critical,keyCertSign,cRLSign\n"
        f"{OID_INTERMEDIATE}=DER:05:00\n")
    sh("openssl", "x509", "-req", "-in", "inter.csr", "-CA", "root.pem", "-CAkey", "root.key",
       "-CAcreateserial", "-sha384", "-days", "3000", "-extfile", "inter.ext", "-out", "inter.pem")

    sh("openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", "leaf.key")
    sh("openssl", "req", "-new", "-key", "leaf.key",
       "-subj", "/C=GB/O=Etudes U4 Test/CN=U4 Test Leaf", "-out", "leaf.csr")
    pathlib.Path("leaf.ext").write_text(
        "basicConstraints=critical,CA:FALSE\n"
        "keyUsage=critical,digitalSignature\n"
        f"{OID_LEAF}=DER:05:00\n")
    sh("openssl", "x509", "-req", "-in", "leaf.csr", "-CA", "inter.pem", "-CAkey", "inter.key",
       "-CAcreateserial", "-sha384", "-days", "400", "-extfile", "leaf.ext", "-out", "leaf.pem")

    # An unrelated root, for the substituted-anchor negatives.
    sh("openssl", "ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", "evil.key")
    sh("openssl", "req", "-x509", "-new", "-key", "evil.key", "-sha384", "-days", "3650",
       "-subj", "/C=GB/O=Not Apple/CN=Unrelated Root", "-out", "evil.pem")

    # A leaf with a chain but WITHOUT the Apple leaf OID.
    pathlib.Path("plain.ext").write_text("basicConstraints=critical,CA:FALSE\n")
    sh("openssl", "x509", "-req", "-in", "leaf.csr", "-CA", "inter.pem", "-CAkey", "inter.key",
       "-CAcreateserial", "-sha384", "-days", "400", "-extfile", "plain.ext", "-out", "plainleaf.pem")

    for f in ("root", "inter", "leaf", "evil", "plainleaf"):
        sh("openssl", "x509", "-in", f"{f}.pem", "-outform", "DER", "-out", f"{f}.der")

    d = {f: pathlib.Path(f"{f}.der").read_bytes() for f in
         ("root", "inter", "leaf", "evil", "plainleaf")}
    x5c = [base64.b64encode(d[f]).decode() for f in ("leaf", "inter", "root")]

    def sign(data: bytes) -> bytes:
        p = subprocess.run(["openssl", "dgst", "-sha256", "-sign", "leaf.key"],
                           input=data, capture_output=True, check=True)
        return der_to_raw(p.stdout, 32)

    def jws(payload, chain=None, alg="ES256"):
        h = b64u(json.dumps({"alg": alg, "x5c": chain if chain is not None else x5c},
                            separators=(",", ":")).encode())
        p = b64u(json.dumps(payload, separators=(",", ":")).encode())
        return f"{h}.{p}.{b64u(sign(f'{h}.{p}'.encode()))}"

    # RELATIVE TO THE ACTUAL CLOCK, not a frozen constant. A hard-coded epoch
    # was used first and it produced a false failure that looked like a defect:
    # every fixture derived as EXPIRED because the constant had aged past real
    # now(), so a correct writer scheduled quarantine and an entitlement
    # assertion failed. Fixtures that encode "thirty days from now" must mean it.
    NOW = int(time.time() * 1000)
    MONTH = 2592000000
    TOKEN = "aaaaaaaa-0000-4000-8000-000000000001"

    def tx(**over):
        base = {
            "originalTransactionId": "2000000999999999", "transactionId": "2000000999999999",
            "bundleId": "com.sdsongs.etudes", "productId": "com.sdsongs.etudes.connected.monthly",
            "subscriptionGroupIdentifier": "22252441", "purchaseDate": NOW,
            "originalPurchaseDate": NOW, "expiresDate": NOW + MONTH, "quantity": 1,
            "type": "Auto-Renewable Subscription", "inAppOwnershipType": "PURCHASED",
            "signedDate": NOW, "environment": "Sandbox", "transactionReason": "PURCHASE",
            "appAccountToken": TOKEN, "storefront": "GBR", "price": 2990, "currency": "GBP"}
        base.update(over)
        return base

    def ri(**over):
        base = {
            "originalTransactionId": "2000000999999999",
            "autoRenewProductId": "com.sdsongs.etudes.connected.monthly",
            "productId": "com.sdsongs.etudes.connected.monthly", "autoRenewStatus": 1,
            "renewalDate": NOW + MONTH, "signedDate": NOW, "environment": "Sandbox",
            "recentSubscriptionStartDate": NOW, "renewalPrice": 2990, "currency": "GBP"}
        base.update(over)
        return base

    def note(ntype="SUBSCRIBED", subtype="INITIAL_BUY", uuid="3f1c0e2a-77ac-4f1d-9f36-9a5b2c1d0e77",
             txp=None, rip=None, env="Sandbox", status=1, omit_renewal=False, extra=None):
        data = {"bundleId": "com.sdsongs.etudes", "bundleVersion": "131",
                "environment": env, "status": status,
                "signedTransactionInfo": jws(txp if txp is not None else tx())}
        if not omit_renewal:
            data["signedRenewalInfo"] = jws(rip if rip is not None else ri())
        body = {"notificationType": ntype, "notificationUUID": uuid, "version": "2.0",
                "signedDate": NOW, "data": data}
        if subtype:
            body["subtype"] = subtype
        if extra:
            body.update(extra)
        return body

    good = jws(note())
    gp = good.split(".")

    def reheader(header_obj, payload_seg=None, sig_seg=None):
        h = b64u(json.dumps(header_obj, separators=(",", ":")).encode())
        return f"{h}.{payload_seg or gp[1]}.{sig_seg if sig_seg is not None else gp[2]}"

    # Tampered NESTED transaction, with the ENVELOPE CORRECTLY RE-SIGNED.
    # This is the fixture that catches trusting an inner JWS because the outer
    # one verified.
    inner = note()["data"]["signedTransactionInfo"].split(".")
    tampered_inner = f"{inner[0]}.{b64u(json.dumps(tx(expiresDate=NOW + 99 * MONTH), separators=(',', ':')).encode())}.{inner[2]}"
    # ITS OWN UUID. Reusing the good notification's uuid made this fixture a
    # REPLAY: ingestion deduplicated it, correctly, and the assertion then scored
    # the previous notification's row instead. A negative fixture that is
    # silently deduplicated tests nothing.
    n = note(uuid="f0000000-77ac-4f1d-9f36-9a5b2c1d0e77")
    n["data"]["signedTransactionInfo"] = tampered_inner
    tampered_nested_tx = jws(n)

    fixtures = {
        # ---- accepted
        "good": good,
        "good_expired": jws(note("EXPIRED", "VOLUNTARY", "6f1c0e2a-77ac-4f1d-9f36-9a5b2c1d0e77",
                                 txp=tx(expiresDate=NOW - MONTH), rip=ri(renewalDate=NOW - MONTH,
                                 autoRenewStatus=0, signedDate=NOW + 7200000), status=2)),
        "good_grace": jws(note("DID_FAIL_TO_RENEW", "GRACE_PERIOD",
                               "7f1c0e2a-77ac-4f1d-9f36-9a5b2c1d0e77",
                               txp=tx(expiresDate=NOW - 3600000),
                               rip=ri(renewalDate=NOW - 3600000, isInBillingRetryPeriod=True,
                                      gracePeriodExpiresDate=NOW + 16 * 86400000,
                                      signedDate=NOW + 7200000), status=4)),
        "good_unmapped": jws(note("DID_RENEW", "", "8f1c0e2a-77ac-4f1d-9f36-9a5b2c1d0e77",
                                  txp=tx(appAccountToken="bbbbbbbb-0000-4000-8000-000000000009",
                                         originalTransactionId="2000000000000777"),
                                  rip=ri(originalTransactionId="2000000000000777"))),
        "good_no_token": jws(note("DID_RENEW", "", "9f1c0e2a-77ac-4f1d-9f36-9a5b2c1d0e77",
                                  txp=tx(appAccountToken=None))),
        "good_production_env": jws(note("DID_RENEW", "", "af1c0e2a-77ac-4f1d-9f36-9a5b2c1d0e77",
                                        env="Production")),
        "test_notification": jws({"notificationType": "TEST",
                                  "notificationUUID": "bf1c0e2a-77ac-4f1d-9f36-9a5b2c1d0e77",
                                  "version": "2.0", "signedDate": NOW,
                                  "data": {"bundleId": "com.sdsongs.etudes",
                                           "environment": "Sandbox"}}),
        # ---- B-25: incomplete, must NOT write and must NOT schedule cleanup
        "incomplete_no_renewal_info": jws(note("DID_RENEW", "", "cf1c0e2a-77ac-4f1d-9f36-9a5b2c1d0e77",
                                               omit_renewal=True, txp=tx(expiresDate=None))),
        "incomplete_no_signed_date": jws(note("DID_RENEW", "", "df1c0e2a-77ac-4f1d-9f36-9a5b2c1d0e77",
                                              rip=ri(signedDate=None))),
        # B-25 Limb A: renewalDate absent, expiresDate present -> MUST still apply.
        "fallback_expires_date": jws(note("DID_RENEW", "", "ef1c0e2a-77ac-4f1d-9f36-9a5b2c1d0e77",
                                          rip=ri(renewalDate=None, signedDate=NOW + 10800000))),
        # ---- negatives, all must be refused
        "tampered_payload": f"{gp[0]}.{b64u(json.dumps(note('EXPIRED'), separators=(',', ':')).encode())}.{gp[2]}",
        "substituted_root": reheader({"alg": "ES256", "x5c": [x5c[0], x5c[1],
                                      base64.b64encode(d['evil']).decode()]}),
        "alg_none": reheader({"alg": "none", "x5c": x5c}, sig_seg=""),
        "alg_rs256": reheader({"alg": "RS256", "x5c": x5c}),
        "no_x5c": reheader({"alg": "ES256"}),
        "chain_too_short": reheader({"alg": "ES256", "x5c": [x5c[0]]}),
        "chain_reordered": reheader({"alg": "ES256", "x5c": [x5c[2], x5c[1], x5c[0]]}),
        "leaf_without_apple_oid": jws(note(), chain=[base64.b64encode(d['plainleaf']).decode(),
                                                     x5c[1], x5c[2]]),
        "tampered_nested_tx": tampered_nested_tx,
        "not_a_jws": "this-is-not-a-jws",
        "two_parts": f"{gp[0]}.{gp[1]}",
        # ---- anchors
        "test_root_der_b64": base64.b64encode(d["root"]).decode(),
        "apple_root_der_b64": anchor_b64_from_source(),
        "binding_token": TOKEN,
    }

    # The REAL Apple link. Fetched rather than committed, because a vendored
    # binary in the repo would be one more thing to keep honest — and if the
    # network is unavailable the harness says so instead of silently skipping.
    try:
        with urllib.request.urlopen(APPLE_WWDR_G6_URL, timeout=15) as r:
            fixtures["apple_wwdr_der_b64"] = base64.b64encode(r.read()).decode()
    except Exception as e:  # noqa: BLE001
        print(f"  WARN: could not fetch Apple WWDR G6 ({e}). Real-chain assertions will SKIP.",
              file=sys.stderr)
        fixtures["apple_wwdr_der_b64"] = None

    (WORK / "fixtures.json").write_text(json.dumps(fixtures, indent=1))
    print(f"  fixtures -> {WORK / 'fixtures.json'}  ({len(fixtures)} entries)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
