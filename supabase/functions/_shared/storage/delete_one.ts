// Single-object Storage deletes for the lifecycle Edge functions.
//
// WHY THIS EXISTS. supabase-js `storage.remove()` uses the BULK route
// (`DELETE /storage/v1/object/{bucket}` with prefixes). In storage-api's S3
// adapter, both the pinned v1.68.1 and public master on 2026-09-18, that route
// checks only REJECTED requests and never reads the per-key `Errors` S3
// `DeleteObjects` returns with HTTP 200 — so a per-key failure commits the
// metadata-row deletion while the bytes remain. The SINGLE-object route
// (`DELETE /storage/v1/object/{bucket}/{path}` → object.ts deleteObject) deletes
// the row and that version's bytes in one storage transaction and rolls the row
// back on a backend error. `remove([oneKey])` still takes the bulk route, so it
// is not a substitute.
//
// WHAT THIS DOES NOT DO. It does not prove hosted behaviour (hosted equivalence
// to the inspected code is unverified), it does not fix storage-api's own
// clean-up of superseded or refused upload versions, and it cannot see or
// remove bytes an earlier bulk delete may have orphaned.
//
// NOTHING SECRET IS LOGGED OR RETURNED. Errors carry the step, the HTTP status,
// the storage status and code, and the object path — never a header, key or body.

/** Officially documented minimum Edge wall clock and request idle timeout: 150 s
 *  (supabase.com/docs/guides/functions/limits, read 2026-09-18). One deadline per
 *  invocation covers every storage list and delete, leaving 50 s of headroom for
 *  the remaining row steps and the response. */
export const STORAGE_DEADLINE_MS = 100_000;
export const DELETE_POOL = 4;
export const PER_REQUEST_TIMEOUT_MS = 15_000;

export class StorageDeleteError extends Error {
  constructor(readonly step: string, message: string) {
    super(message);
  }
}

export type DeleteOutcome = "deleted" | "absent";

export interface StorageDeleteContext {
  /** Project URL, e.g. SUPABASE_URL. */
  url: string;
  /** Server-side service credential. Never logged. */
  key: string;
  /** Absolute epoch-ms deadline for the whole invocation's storage work. */
  deadline: number;
  /** Injection point for tests only. */
  fetchImpl?: typeof fetch;
}

export function storageContext(url: string, key: string, startedAt = Date.now()): StorageDeleteContext {
  return { url, key, deadline: startedAt + STORAGE_DEADLINE_MS };
}

/** Throws a deadline failure once the invocation's storage budget is spent.
 *  Called before every list page and before every delete is started. */
export function assertBeforeDeadline(ctx: StorageDeleteContext, step: string): void {
  if (Date.now() >= ctx.deadline) {
    throw new StorageDeleteError(`${step}.deadline`, "invocation storage deadline reached");
  }
}

/** Runs ONE storage call (a list through the SDK) inside the invocation budget.
 *
 *  The call gets an abort signal capped by the per-request limit AND the time
 *  left before the deadline, and is also raced against that same budget — so a
 *  request, or a response body, that hangs cannot outlive the budget even if the
 *  signal is ignored somewhere below. After it returns, the deadline is checked
 *  AGAIN: a list that comes back after the deadline must not let the next,
 *  destructive stage start. Failures are normalised to a labelled
 *  StorageDeleteError carrying no secret. The SDK's own `{ error }` result is
 *  returned unchanged for the caller to handle as before. */
export async function withStorageDeadline<T>(
  ctx: StorageDeleteContext, step: string, run: (signal: AbortSignal) => Promise<T>,
): Promise<T> {
  assertBeforeDeadline(ctx, step);
  const budget = Math.max(1, Math.min(PER_REQUEST_TIMEOUT_MS, ctx.deadline - Date.now()));
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), budget);
  let result: T;
  try {
    result = await Promise.race([
      run(controller.signal),
      new Promise<never>((_, reject) => {
        controller.signal.addEventListener("abort", () =>
          reject(new StorageDeleteError(`${step}.timeout`, "storage request exceeded its time budget")), { once: true });
      }),
    ]);
  } catch (e) {
    if (e instanceof StorageDeleteError) throw e;
    throw new StorageDeleteError(`${step}.request`, `storage request failed (${e instanceof Error ? e.name : "error"})`);
  } finally {
    clearTimeout(timer);
  }
  assertBeforeDeadline(ctx, step);
  return result;
}

/** Encodes each `/`-separated segment; separators are kept. Empty, `.` and `..`
 *  segments are refused before anything is sent. */
export function encodeObjectPath(path: string): string {
  const segments = path.split("/");
  for (const s of segments) {
    if (s === "" || s === "." || s === "..") {
      throw new StorageDeleteError("storage.encode", `invalid object path segment in ${JSON.stringify(path)}`);
    }
  }
  return segments.map(encodeURIComponent).join("/");
}

/** The ONLY response treated as "absent" is the exact storage not-found shape,
 *  pinned on the local stack 2026-09-18: HTTP 400 with body
 *  {"statusCode":"404","error":"not_found","code":"NoSuchKey"}. Every other
 *  non-2xx, and any body that is not that JSON, is a failure.
 *
 *  "Absent" means the metadata row is absent NOW. It is not evidence that bytes
 *  an earlier bulk delete may have left behind were ever removed. */
export function classifyDeleteResponse(status: number, bodyText: string): DeleteOutcome | { failure: string } {
  if (status >= 200 && status < 300) return "deleted";
  let body: unknown;
  try {
    body = JSON.parse(bodyText);
  } catch {
    return { failure: `status=${status} unparseable body` };
  }
  const b = (body && typeof body === "object") ? body as Record<string, unknown> : {};
  if (status === 400 && b.statusCode === "404" && b.error === "not_found" && b.code === "NoSuchKey") {
    return "absent";
  }
  const sc = typeof b.statusCode === "string" ? b.statusCode : "?";
  const code = typeof b.code === "string" ? b.code : "?";
  return { failure: `status=${status} statusCode=${sc} code=${code}` };
}

/** One single-object DELETE. */
export async function deleteOne(
  ctx: StorageDeleteContext, bucket: string, path: string, step: string,
): Promise<DeleteOutcome> {
  assertBeforeDeadline(ctx, step);
  const timeout = Math.min(PER_REQUEST_TIMEOUT_MS, Math.max(1, ctx.deadline - Date.now()));
  const target = `${ctx.url}/storage/v1/object/${encodeURIComponent(bucket)}/${encodeObjectPath(path)}`;
  let res: Response;
  try {
    res = await (ctx.fetchImpl ?? fetch)(target, {
      method: "DELETE",
      headers: { apikey: ctx.key, Authorization: `Bearer ${ctx.key}` },
      signal: AbortSignal.timeout(timeout),
    });
  } catch (e) {
    const kind = e instanceof Error ? e.name : "error";
    throw new StorageDeleteError(`${step}.request`, `${path}: request failed (${kind})`);
  }
  let text = "";
  try {
    text = await res.text();
  } catch {
    throw new StorageDeleteError(`${step}.response`, `${path}: status=${res.status} body unreadable`);
  }
  const outcome = classifyDeleteResponse(res.status, text);
  if (outcome === "deleted" || outcome === "absent") return outcome;
  throw new StorageDeleteError(`${step}.delete`, `${path}: ${outcome.failure}`);
}

/** Deletes every path, at most `pool` at a time.
 *
 *  On the FIRST failure, or once the deadline has passed, no further delete is
 *  started; every request already in flight is allowed to settle (each is bounded
 *  by the deadline through its own abort signal) BEFORE this returns or throws.
 *  That is not a hard atomic stop: an aborted request may still complete on the
 *  server, which is why the callers re-list afterwards. */
export async function deleteAll(
  ctx: StorageDeleteContext, bucket: string, paths: string[], step: string, pool = DELETE_POOL,
): Promise<{ deleted: number; absent: number; started: number }> {
  let next = 0;
  let started = 0;
  let deleted = 0;
  let absent = 0;
  let firstError: unknown = null;

  const worker = async () => {
    while (firstError === null) {
      if (Date.now() >= ctx.deadline) {
        firstError ??= new StorageDeleteError(`${step}.deadline`, "invocation storage deadline reached");
        return;
      }
      const i = next++;
      if (i >= paths.length) return;
      started++;
      try {
        const outcome = await deleteOne(ctx, bucket, paths[i], step);
        if (outcome === "deleted") deleted++;
        else absent++;
      } catch (e) {
        firstError ??= e;
        return;
      }
    }
  };

  // Workers never reject, so this waits for every in-flight request to settle.
  await Promise.all(Array.from({ length: Math.min(pool, paths.length) }, worker));
  if (firstError !== null) throw firstError;
  // Settled past the deadline: fail rather than let the next stage begin late.
  assertBeforeDeadline(ctx, `${step}.settled`);
  return { deleted, absent, started };
}
