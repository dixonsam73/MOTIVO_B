#!/usr/bin/env bash
#
# C-101 — SELF-TEST FOR U2c's ENCLOSING-FUNCTION DETECTOR (u2c_enclosing.py).
#
#   ./supabase/tests/p4/u2c-detector-selftest.sh
#
# WHAT THIS CLAIMS. The corrected detector (1) still attributes both protected
# call sites in the real BackendShim.swift to uploadPost; (2) is not fooled by
# nesting, protocol requirements, comments or string literals; and (3) — the
# point — STILL CATCHES a protected call moved outside uploadPost, for EACH of
# the two call sites and three destinations. A detector that passed everything
# would pass (1) and (2) and fail (3).
#
# DISPOSABLE FIXTURES ONLY. Mutated sources are generated in a temp directory
# from a COPY of BackendShim.swift. The real file is never written; its sha256 is
# checked before and after. Each negative fixture replaces ONLY the original call
# expression with a placeholder (so enclosing braces, e.g. `for item in … {`,
# survive) and inserts ONE balanced statement at its destination, then proves:
# the expression and anchor each occurred once, exactly one live protected call
# remains, U2c's first match is that call, braces balance, the expected
# destination owns it, and U2c's own comparison FAILS.
#
# Destinations precede both protected declarations (loadIncludedAttachments at
# line 1279, uploadStorageObject at 1433), because U2c takes the FIRST match and
# a declaration matches too; a destination after one would fail U2c for the
# wrong reason. See docs/phase-5-c101-prediction.md §3.

set -uo pipefail
cd "$(dirname "$0")/../../.."

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

python3 - "MOTIVO/BackendShim.swift" "$TMPD" <<'PY'
import hashlib, importlib.util, re, sys

BS, TMP = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("u2c_enclosing", "supabase/tests/p4/u2c_enclosing.py")
det = importlib.util.module_from_spec(spec)
spec.loader.exec_module(det)

PASS = FAIL = 0
def is_(tid, got, want, what):
    global PASS, FAIL
    if str(got) == str(want):
        print(f"  \033[32mPASS\033[0m  {tid:<10} {what} = {want}"); PASS += 1
    else:
        print(f"  \033[31mFAIL\033[0m  {tid:<10} {what}: expected '{want}', got '{got}'"); FAIL += 1

def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()

SUM0 = sha(BS)
real = open(BS, encoding="utf-8").read()
PS = r"uploadStorageObject\(from:"
PL = r"loadIncludedAttachments\(for:"

print("\nC-101 — U2c enclosing-function detector self-test\n")

# ---------------------------------------------------------------- the old helper
# VERBATIM logic of the pre-C-101 enclosing() in u2c-acceptance.sh, kept here to
# document the defect being fixed.
def old_enclosing(text, want, nth):
    t = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    t = re.sub(r"^\s*//.*$", "", t, flags=re.M)
    t = re.sub(r"//.*$", "", t, flags=re.M)
    lines = t.split("\n"); seen = 0
    for i, l in enumerate(lines):
        if re.search(want, l):
            seen += 1
            if seen == nth:
                for j in range(i, -1, -1):
                    m = re.match(r"\s*(?:@\w+\s+)?(?:public |private |internal |fileprivate )?func (\w+)", lines[j])
                    if m: return m.group(1)
                return "<none>"
    return "<not-found>"

print("-- discriminator: the pre-C-101 helper on the real file --")
is_("OLD-S", old_enclosing(real, PS, 1), "discardTemporaries", "old helper, uploadStorageObject call site")
is_("OLD-L", old_enclosing(real, PL, 1), "discardTemporaries", "old helper, loadIncludedAttachments call site")

# ---------------------------------------------------------------- positives
print("\n-- positive controls --")
is_("POS-0", det.brace_balance_ok(real), True, "real BackendShim.swift braces balance after masking")
is_("POS-1", det.enclosing(real, PS, 1), "uploadPost", "real file: uploadStorageObject call site")
is_("POS-2", det.enclosing(real, PL, 1), "uploadPost", "real file: loadIncludedAttachments call site")

CALL = '_ = await uploadStorageObject(from: u, bucket: "b", objectPath: "o", contentType: "c")'
FIX = {
"POS-3": f"""final class C {{
    func uploadPost() async {{
        func helperOne() async {{
            func helperTwo() async {{
                {CALL}
            }}
        }}
    }}
}}
""",
"POS-4": f"""protocol P {{
    func uploadPost(_ p: Int) async -> Result<Void, Error>
    var flag: Bool {{ get }}
}}
final class C: P {{
    var flag: Bool {{ true }}
    func realOwner() async {{
        {CALL}
    }}
}}
""",
"DEC-1": f"""final class C {{
    func other() {{
        // uploadStorageObject(from: decoy) {{ unbalanced
        /* outer /* uploadStorageObject(from: nested) {{ */ still a comment {{ */
    }}
    func realOwner() async {{
        {CALL}
    }}
}}
""",
"DEC-2": f'''final class C {{
    func other() {{
        let s = "{{ }} // func fake() {{"
        let t = """
        func fake() {{
        {{{{ uploadStorageObject(from: inString) {{
        """
        _ = (s, t)
    }}
    func realOwner() async {{
        {CALL}
    }}
}}
''',
"DEC-3": """final class C {
    func holder() {
        let s = "uploadStorageObject(from: onlyInAString)"
        _ = s
    }
}
""",
"NONE-1": f"""let topLevel = {CALL.replace('_ = await ', '')}
final class C {{}}
""",
}
EXPECT = {
    "POS-3": ("uploadPost", "call nested two levels inside uploadPost belongs to uploadPost"),
    "POS-4": ("realOwner", "a body-less protocol requirement named uploadPost captures nothing"),
}
for k, (want, what) in EXPECT.items():
    is_(k, det.enclosing(FIX[k], PS, 1), want, what)

print("\n-- decoy controls (comments and strings) --")
is_("DEC-1", det.enclosing(FIX["DEC-1"], PS, 1), "realOwner", "call text and { in // and nested /* */ neither match nor shift depth")
is_("DEC-2", det.enclosing(FIX["DEC-2"], PS, 1), "realOwner", "braces and func text inside \"…\" and \"\"\"…\"\"\" are ignored")
is_("DEC-3", det.enclosing(FIX["DEC-3"], PS, 1), "<not-found>", "the pattern only inside a string literal is not found")
is_("NONE-1", det.enclosing(FIX["NONE-1"], PS, 1), "<none>", "a match in no function is <none>, distinct from <not-found>")

# ---------------------------------------------------------------- negatives
print("\n-- negative controls: each protected call moved outside uploadPost --")
SITES = {
    "S": dict(pattern=PS,
              original='uploadStorageObject(from: prepared.fileURL, bucket: "attachments", objectPath: objectPath, contentType: prepared.contentType)',
              placeholder="c101Placeholder()",
              stmt='_ = await uploadStorageObject(from: URL(fileURLWithPath: "/"), bucket: "b", objectPath: "p", contentType: "c")'),
    "L": dict(pattern=PL,
              original="loadIncludedAttachments(for: sessionID)",
              placeholder="[LocalAttachmentUpload]()",
              stmt="_ = loadIncludedAttachments(for: UUID())"),
}
DESTS = {
    "1": dict(anchor="    private struct PreparedAttachmentUpload {", where="before",
              block=lambda s: f"    func c101MovedOut() async {{\n        {s}\n    }}\n\n",
              owner="c101MovedOut", what="a sibling method after uploadPost"),
    "2": dict(anchor="public final class HTTPBackendPublishService: BackendPublishService {", where="before",
              block=lambda s: f"func c101FreeFunction() async {{\n    {s}\n}}\n\n",
              owner="c101FreeFunction", what="a top-level free function"),
    "3": dict(anchor="    private func deleteFollowRow(follower: String, followed: String) async -> Result<Void, Error> {\n", where="after",
              block=lambda s: f"        func c101NestedHelper() async {{\n            {s}\n        }}\n",
              owner="deleteFollowRow", what="a helper nested inside a different method (deleteFollowRow)"),
}
for sk, site in SITES.items():
    for dk, dest in DESTS.items():
        tid = f"NEG-{sk}{dk}"
        is_(f"{tid}a", real.count(site["original"]), 1, f"original {sk} call expression occurs exactly once")
        is_(f"{tid}b", real.count(dest["anchor"]), 1, f"destination anchor occurs exactly once ({dest['what']})")
        m = real.replace(site["original"], site["placeholder"], 1)
        block = dest["block"](site["stmt"])
        if dest["where"] == "before":
            m = m.replace(dest["anchor"], block + dest["anchor"], 1)
        else:
            m = m.replace(dest["anchor"], dest["anchor"] + block, 1)
        path = f"{TMP}/BackendShim.{tid}.swift"
        open(path, "w", encoding="utf-8").write(m)
        live = det.live_calls(m, site["pattern"])
        is_(f"{tid}c", len(live), 1, "exactly one live protected call remains")
        first = re.search(site["pattern"], det.mask(m))
        is_(f"{tid}d", bool(first) and len(live) == 1 and first.start() == live[0], True, "U2c's first match is that live call, not a declaration")
        is_(f"{tid}e", det.brace_balance_ok(m), True, "fixture braces balance (scope structure preserved)")
        got = det.enclosing(m, site["pattern"], 1)
        is_(f"{tid}f", got, dest["owner"], f"detector reports the destination: {dest['what']}")
        is_(f"{tid}g", "uploadPost-check=" + ("PASS" if got == "uploadPost" else "FAIL"), "uploadPost-check=FAIL",
            "U2c's own comparison FAILS on the displaced call")

print("\n-- guard --")
is_("GUARD", sha(BS), SUM0, "MOTIVO/BackendShim.swift sha256 unchanged")
print(f"\n  passed={PASS} failed={FAIL}\n")
sys.exit(0 if FAIL == 0 else 1)
PY
