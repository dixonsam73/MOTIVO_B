#!/usr/bin/env python3
"""
C-14 discriminator — P5-A.

Re-runnable. Scores five assertions over MOTIVO/*.swift and prints a table.
Run from the repository root:  python3 scripts/c14-discriminator.py

It is a DISCRIMINATOR, not a checker: it is designed to produce a DIFFERENT,
predicted result against pre-fix and post-fix code. The predicted values for
both are recorded in docs/phase-5-a-c14-prediction.md.

Detection rules, stated so they are auditable rather than hidden in a regex:

  * A site is DEBUG-ONLY if it lies inside a `#if DEBUG` region. The `#else`
    branch of such a region is treated as SHIPPING.
  * An IDENTIFIER ARGUMENT is an argument expression naming a backend USER
    identifier, handle, display name or email. Two match rules, because a
    single one produced false positives:
      - NAMED_IDENT_ARGS match as a token anywhere in the expression. These
        names are specific enough that a substring match cannot be a content id.
      - EXACT_IDENT_ARGS must be the WHOLE argument expression. `id` is here
        because a token match flagged `payload.id.uuidString` -- a POST id, not
        a user id. Content identifiers are out of C-14's scope.
  * `ownerKey` is DELIBERATELY EXCLUDED from the identifier set and counted
    separately as A3b. Its only writer, PublishService.setOwnerKey, has only
    DEBUG-only callers (DebugViewerView), so in a Release build `ownerKey`
    resolves to its literal fallback "local-device" and is not a user ID.
    The exclusion is declared, not silent.
"""

import os, re, sys

ROOT = "MOTIVO"

# Argument expressions that carry a backend user identifier / handle / name / email.
NAMED_IDENT_ARGS = {
    "targetUserID", "requesterUserID", "userID", "userId", "user_id",
    "uid", "backendUserID", "appleUserID", "displayName", "handle", "email",
}

# Must be the ENTIRE argument expression -- see the module docstring.
EXACT_IDENT_ARGS = {"id"}

# Counted separately -- see the module docstring.
OWNERKEY_ARGS = {"ownerKey", "key"}

# The eight call sites C-14's fix targets, identified by their event marker.
TARGET_EVENTS = [
    "[FollowStore] request",
    "[FollowStore] approve",
    "[FollowStore] decline",
    "[FollowStore] removeFollower",
    "[FollowStore] unfollow",
    "[FollowStore] simulateRequestFollow",
    "[FollowStore] simulateAcceptFollow",
    "[FollowStore] simulateUnfollow",
]


def scan():
    """Return a list of NSLog call-site records."""
    sites = []
    for dirpath, _dirnames, filenames in os.walk(ROOT):
        for fn in sorted(filenames):
            if not fn.endswith(".swift"):
                continue
            path = os.path.join(dirpath, fn)
            lines = open(path, encoding="utf-8").read().split("\n")
            stack = []  # True where the enclosing region is DEBUG-only
            for i, line in enumerate(lines, 1):
                s = line.strip()
                m = re.match(r"#if\s+(.*)", s)
                if m:
                    cond = m.group(1).strip()
                    stack.append("DEBUG" in cond and not cond.startswith("!"))
                    continue
                if s.startswith("#elseif") or s.startswith("#else"):
                    if stack:
                        stack[-1] = False  # the non-DEBUG branch ships
                    continue
                if s.startswith("#endif"):
                    if stack:
                        stack.pop()
                    continue
                if "NSLog" not in line or s.startswith("//"):
                    continue
                # Gather the full call, which may wrap across lines.
                call, depth, j = "", 0, i - 1
                while j < len(lines):
                    call += lines[j]
                    depth += lines[j].count("(") - lines[j].count(")")
                    j += 1
                    if depth <= 0 and call.count("(") > 0:
                        break
                sites.append({
                    "file": path, "line": i,
                    "debug_only": any(stack),
                    "call": call.strip(),
                })
    return sites


def arg_exprs(call):
    """Argument expressions after the NSLog format string."""
    m = re.search(r"NSLog\s*\((.*)\)\s*$", call, re.S)
    if not m:
        return []
    inner = m.group(1)
    # Drop the leading format string literal.
    fm = re.match(r'\s*"(?:[^"\\]|\\.)*"\s*', inner)
    if not fm:
        return []
    rest = inner[fm.end():]
    if not rest.strip().startswith(","):
        return []
    rest = rest.strip()[1:]
    # Split on top-level commas.
    args, depth, cur = [], 0, ""
    for ch in rest:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            args.append(cur.strip()); cur = ""
        else:
            cur += ch
    if cur.strip():
        args.append(cur.strip())
    return args


def has_ident(call, named, exact=frozenset()):
    for a in arg_exprs(call):
        if a.strip() in exact:
            return True
        for tok in re.findall(r"[A-Za-z_][A-Za-z0-9_]*", a):
            if tok in named:
                return True
    return False


def main():
    if not os.path.isdir(ROOT):
        sys.exit("run from the repository root (no %s/ here)" % ROOT)
    sites = scan()
    ship = [s for s in sites if not s["debug_only"]]
    debug = [s for s in sites if s["debug_only"]]

    targets = [s for s in sites
               if any(ev in s["call"] for ev in TARGET_EVENTS)]

    a1 = sum(1 for s in targets if has_ident(s["call"], NAMED_IDENT_ARGS, EXACT_IDENT_ARGS))
    a2 = len({ev for ev in TARGET_EVENTS
              for s in targets if ev in s["call"]})
    a3a = sum(1 for s in ship if has_ident(s["call"], NAMED_IDENT_ARGS, EXACT_IDENT_ARGS))
    a3b = sum(1 for s in ship if has_ident(s["call"], OWNERKEY_ARGS))
    a4 = len(debug)
    a5 = len(ship)

    rows = [
        ("A1", "targeted FollowStore sites passing an identifier argument", a1),
        ("A2", "targeted diagnostic events still present", a2),
        ("A3a", "SHIPPING sites passing a backend user ID / handle / name / email", a3a),
        ("A3b", "SHIPPING sites passing ownerKey (declared exclusion)", a3b),
        ("A4", "DEBUG-only NSLog sites", a4),
        ("A5", "SHIPPING NSLog call sites (total)", a5),
    ]
    print("C-14 discriminator")
    print("=" * 74)
    for k, desc, v in rows:
        print("%-4s %-60s %4d" % (k, desc, v))
    print("=" * 74)

    if a3a:
        print("\nsites still passing an identifier argument:")
        for s in ship:
            if has_ident(s["call"], NAMED_IDENT_ARGS, EXACT_IDENT_ARGS):
                print("  %s:%d  %s" % (s["file"], s["line"], s["call"][:110]))


if __name__ == "__main__":
    main()
