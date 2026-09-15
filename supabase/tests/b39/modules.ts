// B-39 — derive.ts's entitledAt must agree with the SQL rule.
//
//   B39_PHASE=pre|post deno run --allow-env supabase/tests/b39/modules.ts
//
// entitledAt is diagnostics only ("THE SERVER'S ANSWER IS connected_member()"),
// but it exists so the TypeScript and the SQL agree, so it moves with them.
// Pure: derive.ts has no imports and no I/O.

import { entitledAt, type MembershipState } from "../../functions/_shared/appstore/derive.ts";

const now = new Date();
const days = (n: number) => new Date(now.getTime() + n * 86400_000).toISOString();
const base: MembershipState = {
  product_id: "p", apple_status: 1, renewal_date: days(20), grace_period_expires_date: null,
  is_in_billing_retry: false, auto_renew_status: 1, expiration_intent: null,
  revocation_date: null, renewal_info_signed_date: now.toISOString(),
};

const phase = Deno.env.get("B39_PHASE") ?? "pre";
const predictedFail = phase === "pre" ? new Set(["B39-T1", "B39-T2"]) : new Set<string>();
const failed: string[] = [];
let pass = 0;
const is = (id: string, got: boolean, want: boolean, what: string) => {
  if (got === want) { pass++; console.log(`  PASS  ${id}  ${what} = ${want}`); }
  else { failed.push(id); console.log(`  FAIL  ${id}  ${what}: expected ${want}, got ${got}`); }
};

console.log(`\nB-39 modules — entitledAt (phase ${phase})\n`);
is("B39-T0", entitledAt(base, now), true, "control: active, future renewal");
is("B39-T1", entitledAt({ ...base, apple_status: 5, revocation_date: days(-0.1) }, now), false, "status 5 before expiry is not entitled");
is("B39-T2", entitledAt({ ...base, apple_status: 5, is_in_billing_retry: true, grace_period_expires_date: days(5), renewal_date: days(-1) }, now), false, "status 5 is not rescued by grace");
is("B39-T3", entitledAt({ ...base, revocation_date: days(-30) }, now), true, "an earlier period's refund (status 1) stays entitled");
is("B39-T4", entitledAt({ ...base, apple_status: null, revocation_date: days(-0.1) }, now), true, "status absent: date formula only");
is("B39-T5", entitledAt({ ...base, apple_status: 2, renewal_date: days(-1) }, now), false, "control: expired");

const obs = [...failed].sort().join(" "), prd = [...predictedFail].sort().join(" ");
console.log(`\nB-39 modules tally: ${pass} passed, ${failed.length} failed`);
if (obs === prd) { console.log(`PREDICTION MATCHED (phase ${phase})`); Deno.exit(0); }
console.log(`PREDICTION DEVIATION (phase ${phase})\n  predicted: ${prd}\n  observed:  ${obs}`);
Deno.exit(1);
