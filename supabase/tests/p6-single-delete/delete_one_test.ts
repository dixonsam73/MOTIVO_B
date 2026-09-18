// Unit tests for supabase/functions/_shared/storage/delete_one.ts.
// No network: every request goes to a stubbed fetch. Run with:
//   deno test supabase/tests/p6-single-delete/delete_one_test.ts
import {
  assert,
  assertEquals,
  assertRejects,
  assertThrows,
} from "jsr:@std/assert@1";
import {
  classifyDeleteResponse,
  deleteAll,
  deleteOne,
  encodeObjectPath,
  StorageDeleteError,
  type StorageDeleteContext,
  withStorageDeadline,
} from "../../functions/_shared/storage/delete_one.ts";

const NOT_FOUND = JSON.stringify({ statusCode: "404", error: "not_found", message: "Object not found", code: "NoSuchKey" });
const SECRET = "test-service-key-must-never-appear";

function ctx(fetchImpl: typeof fetch, ms = 60_000): StorageDeleteContext {
  return { url: "http://storage.test", key: SECRET, deadline: Date.now() + ms, fetchImpl };
}
const reply = (status: number, body: string) => () => Promise.resolve(new Response(body, { status }));

// ---- encoding
Deno.test("encode: segments encoded, separators kept", () => {
  assertEquals(encodeObjectPath("users/abc/post 1/a#b.m4a"), "users/abc/post%201/a%23b.m4a");
});
Deno.test("encode: empty, . and .. segments refused", () => {
  for (const p of ["users//x", "users/./x", "users/../x", "/users/x", "users/x/"]) {
    assertThrows(() => encodeObjectPath(p), StorageDeleteError);
  }
});

// ---- classification: ONLY the pinned not-found shape is "absent"
Deno.test("classify: 2xx deleted; the exact pinned not-found is absent", () => {
  assertEquals(classifyDeleteResponse(200, "{}"), "deleted");
  assertEquals(classifyDeleteResponse(400, NOT_FOUND), "absent");
});
Deno.test("classify: every other shape fails", () => {
  const cases: [number, string][] = [
    [400, JSON.stringify({ statusCode: "400", error: "InvalidRequest", code: "InvalidRequest" })], // generic 400
    [400, JSON.stringify({ statusCode: "403", error: "Unauthorized", code: "AccessDenied" })],     // auth
    [401, JSON.stringify({ statusCode: "401", code: "InvalidJWT" })],
    [403, JSON.stringify({ statusCode: "403", code: "AccessDenied" })],
    [404, NOT_FOUND],                                                                             // right body, wrong status
    [400, JSON.stringify({ statusCode: "404", error: "not_found", code: "Other" })],              // partial match
    [500, JSON.stringify({ statusCode: "500", code: "InternalError" })],                          // 5xx
    [503, "<html>gateway</html>"],                                                                // malformed
    [400, ""],                                                                                    // empty
  ];
  for (const [s, b] of cases) {
    const r = classifyDeleteResponse(s, b);
    assert(typeof r === "object" && "failure" in r, `expected failure for ${s} ${b}`);
  }
});

// ---- deleteOne
Deno.test("deleteOne: single-object route, encoded path, key only in headers", async () => {
  let seen: Request | null = null;
  const f = (input: string | URL | Request, init?: RequestInit) => {
    seen = new Request(input, init);
    return Promise.resolve(new Response("{}", { status: 200 }));
  };
  assertEquals(await deleteOne(ctx(f as typeof fetch), "attachments", "users/u 1/p/a.png", "t"), "deleted");
  assertEquals(seen!.method, "DELETE");
  assertEquals(seen!.url, "http://storage.test/storage/v1/object/attachments/users/u%201/p/a.png");
  assert(!seen!.url.includes(SECRET));
  assertEquals(seen!.headers.get("authorization"), `Bearer ${SECRET}`);
});
Deno.test("deleteOne: pinned not-found -> absent", async () => {
  assertEquals(await deleteOne(ctx(reply(400, NOT_FOUND) as typeof fetch), "attachments", "users/u/x.png", "t"), "absent");
});
Deno.test("deleteOne: generic 400 / auth / 5xx / malformed / network all fail, with no secret in the error", async () => {
  const fails: (() => Promise<Response>)[] = [
    reply(400, JSON.stringify({ statusCode: "400", code: "InvalidRequest" })),
    reply(400, JSON.stringify({ statusCode: "403", code: "AccessDenied" })),
    reply(500, JSON.stringify({ statusCode: "500", code: "InternalError" })),
    reply(502, "not json"),
    () => Promise.reject(new TypeError("network down")),
  ];
  for (const f of fails) {
    const e = await assertRejects(() => deleteOne(ctx(f as typeof fetch), "attachments", "users/u/x.png", "t"), StorageDeleteError);
    assert(!e.message.includes(SECRET) && !e.step.includes(SECRET));
  }
});
Deno.test("deleteOne: past the deadline, nothing is sent", async () => {
  let calls = 0;
  const f = () => { calls++; return Promise.resolve(new Response("{}", { status: 200 })); };
  const e = await assertRejects(() => deleteOne(ctx(f as typeof fetch, -1), "attachments", "users/u/x.png", "t"), StorageDeleteError);
  assertEquals(e.step, "t.deadline");
  assertEquals(calls, 0);
});

// ---- deleteAll: pool, first-error stop, drain, deadline
Deno.test("deleteAll: bounded concurrency; all succeed", async () => {
  let inFlight = 0, peak = 0;
  const f = async () => {
    inFlight++; peak = Math.max(peak, inFlight);
    await new Promise((r) => setTimeout(r, 5));
    inFlight--;
    return new Response("{}", { status: 200 });
  };
  const paths = Array.from({ length: 13 }, (_, i) => `users/u/${i}.png`);
  const r = await deleteAll(ctx(f as typeof fetch), "attachments", paths, "t", 4);
  assertEquals(r, { deleted: 13, absent: 0, started: 13 });
  assert(peak <= 4, `peak ${peak}`);
});
Deno.test("deleteAll: first error stops scheduling and in-flight requests settle before it throws", async () => {
  let started = 0, settled = 0;
  const f = async (input: string | URL | Request) => {
    started++;
    const url = String(input instanceof Request ? input.url : input);
    if (url.endsWith("/1.png")) return new Response(JSON.stringify({ statusCode: "500", code: "InternalError" }), { status: 500 });
    await new Promise((r) => setTimeout(r, 30)); // the others are still in flight when #1 fails
    settled++;
    return new Response("{}", { status: 200 });
  };
  const paths = Array.from({ length: 20 }, (_, i) => `users/u/${i}.png`);
  await assertRejects(() => deleteAll(ctx(f as typeof fetch), "attachments", paths, "t", 4), StorageDeleteError);
  assertEquals(started, 4, "only the first pool-full were ever started");
  assertEquals(settled, 3, "every other in-flight request settled BEFORE deleteAll threw");
});
Deno.test("deleteAll: deadline stops new candidates and fails with a deadline step", async () => {
  let started = 0;
  const f = async () => { started++; await new Promise((r) => setTimeout(r, 40)); return new Response("{}", { status: 200 }); };
  const paths = Array.from({ length: 20 }, (_, i) => `users/u/${i}.png`);
  const e = await assertRejects(() => deleteAll(ctx(f as typeof fetch, 60), "attachments", paths, "t", 2), StorageDeleteError);
  assert(e.step.endsWith(".deadline") || e.step.endsWith(".request"), e.step);
  assert(started < 20, `started ${started}`);
});
Deno.test("deleteAll: absent is counted, not failed", async () => {
  const r = await deleteAll(ctx(reply(400, NOT_FOUND) as typeof fetch), "avatars", ["users/u/avatar.jpg"], "t");
  assertEquals(r, { deleted: 0, absent: 1, started: 1 });
});

// ---- withStorageDeadline: the SDK list call, bounded
Deno.test("bounded list: a HANGING call is abandoned at the budget with a labelled timeout, and its signal is aborted", async () => {
  let seenSignal: AbortSignal | null = null;
  const started = Date.now();
  const e = await assertRejects(
    () => withStorageDeadline(ctx(fetch, 80), "storage.list:x", (signal) => { seenSignal = signal; return new Promise(() => {}); }),
    StorageDeleteError,
  );
  assertEquals(e.step, "storage.list:x.timeout");
  assert(Date.now() - started < 1_000, "abandoned promptly at the budget, not left hanging");
  assert(seenSignal!.aborted, "the SDK call was handed a signal, and it was aborted");
});
Deno.test("bounded list: a call that RETURNS after the deadline is refused, so no later stage can start", async () => {
  // The run ignores its signal and resolves late; the race may win or the post-await
  // check may — either way it must fail, never return the late result.
  const late = (_: AbortSignal) => new Promise((r) => setTimeout(() => r({ data: [], error: null }), 60));
  const e = await assertRejects(() => withStorageDeadline(ctx(fetch, 30), "storage.list:y", late), StorageDeleteError);
  assert(e.step === "storage.list:y.timeout" || e.step === "storage.list:y.deadline", e.step);
});
Deno.test("bounded list: past the deadline, the call is never started", async () => {
  let calls = 0;
  await assertRejects(() => withStorageDeadline(ctx(fetch, -1), "s", () => { calls++; return Promise.resolve(1); }), StorageDeleteError);
  assertEquals(calls, 0);
});
Deno.test("bounded list: a normal call returns its result unchanged (SDK { error } passes through)", async () => {
  const r = await withStorageDeadline(ctx(fetch), "s", () => Promise.resolve({ data: null, error: { message: "sdk error" } }));
  assertEquals(r, { data: null, error: { message: "sdk error" } });
});
Deno.test("bounded list: a rejecting call becomes a labelled error with no secret", async () => {
  const e = await assertRejects(() => withStorageDeadline(ctx(fetch), "s", () => Promise.reject(new TypeError(SECRET))), StorageDeleteError);
  assertEquals(e.step, "s.request");
  assert(!e.message.includes(SECRET));
});
Deno.test("deleteAll: finishing after the deadline fails rather than letting the next stage start late", async () => {
  // Each request is aborted at the deadline, so the pool fails; it must not return success.
  const slow = () => new Promise<Response>((r) => setTimeout(() => r(new Response("{}", { status: 200 })), 80));
  await assertRejects(() => deleteAll(ctx(slow as typeof fetch, 40), "attachments", ["users/u/a.png"], "t"), StorageDeleteError);
});
