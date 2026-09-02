// U7 programmable Apple stand-in.
//
// Modelled on supabase/tests/u5/applestub.ts, with ONE deliberate difference:
// the scenario is keyed BY originalTransactionId rather than global. U7's
// authority rule is identity-scoped across environments, so the load-bearing
// cases need Apple to answer DIFFERENTLY for two rows of the SAME identity —
// a lapsed Sandbox row alongside a live Production one (D-6), and one
// environment failing while the other succeeds (D-8). A global scenario cannot
// express either, and testing them separately would not test them at all.
const F: Record<string, string> = JSON.parse(await Deno.readTextFile("/probe/fixtures.json"));

interface Plan {
  ri?: string;       // renewal-info fixture: attest_ri (entitled) | attest_ri_lapsed
  tx?: string;       // transaction fixture
  status?: number;   // Apple subscription status
  http?: number;     // force a non-200
  empty?: boolean;   // 200 with no data
  garbage?: boolean; // 200 with an unparseable body
  hang?: boolean;    // never answer — the timeout case
}
let plans: Record<string, Plan> = {};
let calls: { otid: string; env: string }[] = [];

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const path = url.pathname;

  if (path === "/__control") {
    plans = await req.json();
    calls = [];
    return json(200, { ok: true });
  }
  if (path === "/__calls") return json(200, { calls });

  if (req.method === "GET" && path.startsWith("/inApps/v1/subscriptions/")) {
    const otid = path.split("/").pop()!;
    calls.push({ otid, env: url.searchParams.get("env") ?? "?" });
    const p = plans[otid] ?? plans["*"] ?? {};

    if (p.hang) { await new Promise((r) => setTimeout(r, 60_000)); }
    if (p.http && p.http !== 200) return json(p.http, { errorCode: 5000000 });
    if (p.garbage) return new Response("not json at all", { status: 200, headers: { "content-type": "application/json" } });
    if (p.empty) return json(200, { data: [] });

    const entry: Record<string, unknown> = {
      originalTransactionId: otid,
      status: p.status ?? 2,
      signedRenewalInfo: F[p.ri ?? "attest_ri_lapsed"],
      signedTransactionInfo: F[p.tx ?? "attest_ok"],
    };
    return json(200, { data: [{ subscriptionGroupIdentifier: "g1", lastTransactions: [entry] }] });
  }
  return json(404, { errorCode: 4040010 });
});
