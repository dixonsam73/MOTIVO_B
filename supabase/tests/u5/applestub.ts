// A programmable stand-in for the App Store Server API. LOCAL TEST ONLY.
//
// IT EXISTS FOR ONE THING THE OTHER SUITES CANNOT REACH: THE OUTBOUND CALL ORDER.
//
// A30 is not "the row ends up correct". A30 is "Set App Account Token happened,
// THEN an independent re-read happened, THEN establishment happened". An
// implementation that establishes on the strength of the PUT's own 200 produces
// an identical final row and is WRONG — Apple documents no read-after-write
// guarantee, and P12 already proved Apple-side propagation is real and looks
// exactly like misconfiguration. So this stub records every request in order and
// the suite asserts the SEQUENCE, not just the outcome.
//
// It signs nothing. Every JWS it serves is a pre-minted fixture from
// make-fixtures.py, signed by the throwaway test CA, so the endpoint under test
// still performs real signature verification against the anchor its copy carries.

const F = JSON.parse(await Deno.readTextFile("/probe/fixtures.json"));

interface Scenario {
  /** Fixture name for signedTransactionInfo BEFORE any PUT. */
  txBefore: string | null;
  /** Fixture name for signedTransactionInfo AFTER a successful PUT. */
  txAfter: string | null;
  ri: string;
  /** Status-read behaviour: http status to return instead of 200. */
  statusHttp?: number;
  /** PUT behaviour. */
  putHttp?: number;
  putErrorCode?: number;
  /** Omit the lastTransactions entry entirely. */
  empty?: boolean;
}

let scenario: Scenario = { txBefore: "attest_ok", txAfter: "attest_ok", ri: "attest_ri" };
let putCount = 0;
let calls: string[] = [];

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

Deno.serve((req) => {
  const url = new URL(req.url);
  const path = url.pathname;

  // ---- control plane, not part of the emulated API ----
  if (path === "/__control") {
    return req.json().then((s: Scenario) => {
      scenario = s;
      putCount = 0;
      calls = [];
      return json(200, { ok: true });
    });
  }
  if (path === "/__calls") return json(200, { calls, putCount });

  // ---- PUT /inApps/v1/transactions/{id}/appAccountToken ----
  if (req.method === "PUT" && path.endsWith("/appAccountToken")) {
    const id = path.split("/")[4] ?? "";
    calls.push(`PUT:${id}`);
    if (scenario.putHttp && scenario.putHttp !== 200) {
      return json(scenario.putHttp, scenario.putErrorCode ? { errorCode: scenario.putErrorCode } : {});
    }
    putCount++;
    // APPLE ANSWERS 200 WITH AN EMPTY BODY. Emulated faithfully, because getting
    // this wrong in the client is precisely the defect the U5c battery caught.
    return new Response("", { status: 200 });
  }

  // ---- GET /inApps/v1/subscriptions/{id} ----
  if (req.method === "GET" && path.startsWith("/inApps/v1/subscriptions/")) {
    const id = path.split("/").pop() ?? "";
    calls.push(`GET:${id}`);
    if (scenario.statusHttp && scenario.statusHttp !== 200) {
      return json(scenario.statusHttp, { errorCode: 5000000 });
    }
    if (scenario.empty) return json(200, { data: [] });

    const txName = putCount > 0 ? scenario.txAfter : scenario.txBefore;
    const entry: Record<string, unknown> = {
      originalTransactionId: "2000000999999999",
      status: 1,
      signedRenewalInfo: F[scenario.ri],
    };
    if (txName) entry.signedTransactionInfo = F[txName];
    return json(200, {
      environment: "Sandbox",
      bundleId: "com.sdsongs.etudes",
      data: [{ subscriptionGroupIdentifier: "22252441", lastTransactions: [entry] }],
    });
  }

  calls.push(`${req.method}:${path}`);
  return json(404, { errorCode: 4040010 });
});
