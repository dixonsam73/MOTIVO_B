#!/usr/bin/env python3
"""
C-101 — the enclosing-function detector behind U2c-2 and U2c-4.

    python3 supabase/tests/p4/u2c_enclosing.py FILE PATTERN NTH
        prints the OUTERMOST function enclosing the NTH match of PATTERN,
        '<none>' if that match is in no function, '<not-found>' if there is no
        NTH match.

WHY IT EXISTS. The previous helper stripped comments by regex, found the match,
then scanned BACKWARDS to the nearest `func <name>` line, ignoring brace depth.
C-65 nested `func discardTemporaries()` inside `uploadPost` ahead of both
protected call sites, so the scan stopped at the helper and U2c-2/U2c-4 failed
although both call sites are inside `uploadPost`.

HOW IT WORKS.
  1. mask()   — comments (line; block, depth-counted because Swift nests them)
                and string literals ("…" with escapes, and \"\"\"…\"\"\") are
                replaced by spaces. Newlines are kept, so offsets and line
                numbers are unchanged.
  2. scopes   — over masked text, `func <name>` sets a pending name that the
                next `{` consumes; any other declaration keyword, or a `}`,
                discards it first, so a body-less protocol requirement never
                captures a later brace. `}` pops.
  3. report   — the OUTERMOST named function on the scope stack at the match:
                a call inside a helper nested in `uploadPost` belongs to
                `uploadPost`, since a nested function cannot be called from
                outside it.

HEURISTIC LIMITS, STATED ACCURATELY. This is a bounded source-inspection
heuristic, not a Swift parser. A string literal is masked WHOLE, including any
`\\( … )` interpolation — and interpolation can contain executable expressions
and closures, which are then hidden from the scan. Also not modelled: `#if`
branches with unbalanced braces, and a closure used as a default argument in a
function signature. The guarantee is exactly what U2c asserts and what
u2c-detector-selftest.sh exercises, nothing broader.
"""

import re
import sys

__all__ = ["mask", "enclosing", "brace_balance_ok", "live_calls"]


def mask(text: str) -> str:
    out = list(text)
    n = len(text)

    def blank(a: int, b: int) -> None:
        for k in range(a, b):
            if out[k] != "\n":
                out[k] = " "

    i = 0
    while i < n:
        if text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            blank(i, j)
            i = j
            continue
        if text.startswith("/*", i):
            depth, j = 0, i
            while j < n:
                if text.startswith("/*", j):
                    depth += 1
                    j += 2
                    continue
                if text.startswith("*/", j):
                    depth -= 1
                    j += 2
                    if depth == 0:
                        break
                    continue
                j += 1
            blank(i, j)
            i = j
            continue
        if text.startswith('"""', i):
            j = text.find('"""', i + 3)
            j = n if j < 0 else j + 3
            blank(i, j)
            i = j
            continue
        if text[i] == '"':
            j = i + 1
            while j < n and text[j] not in '"\n':
                if text.startswith("\\(", j):
                    # Skip an interpolation, so a quote inside it does not end
                    # the literal early. Its contents are masked with the rest.
                    j += 2
                    depth = 1
                    while j < n and depth > 0 and text[j] != "\n":
                        ch = text[j]
                        if ch == "(":
                            depth += 1
                        elif ch == ")":
                            depth -= 1
                        elif ch == '"':
                            k = text.find('"', j + 1)
                            j = n if k < 0 else k
                        j += 1
                    continue
                j += 2 if text[j] == "\\" else 1
            if j < n and text[j] == '"':
                j += 1
            blank(i, j)
            i = j
            continue
        i += 1
    return "".join(out)


_TOKEN = re.compile(
    r"\bfunc\s+([A-Za-z_]\w*)"
    r"|\b(var|let|init|deinit|subscript|case|struct|class|enum|protocol|extension|actor|typealias|import)\b"
    r"|([{}])"
)


def _stack_at(masked: str, pos: int) -> list:
    stack, pending = [], None
    for m in _TOKEN.finditer(masked, 0, pos):
        if m.group(1):
            pending = m.group(1)
        elif m.group(2):
            pending = None
        elif m.group(3) == "{":
            stack.append(pending)
            pending = None
        else:
            if stack:
                stack.pop()
            pending = None
    return stack


def enclosing(text: str, pattern: str, nth: int) -> str:
    masked = mask(text)
    matches = list(re.finditer(pattern, masked))
    if len(matches) < nth or nth < 1:
        return "<not-found>"
    for name in _stack_at(masked, matches[nth - 1].start()):
        if name:
            return name
    return "<none>"


def brace_balance_ok(text: str) -> bool:
    depth = 0
    for ch in mask(text):
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth < 0:
                return False
    return depth == 0


_DECL_BEFORE = re.compile(r"\bfunc\s+$")


def live_calls(text: str, pattern: str) -> list:
    """Offsets of pattern matches in code that are not the function's own declaration."""
    masked = mask(text)
    return [m.start() for m in re.finditer(pattern, masked)
            if not _DECL_BEFORE.search(masked[max(0, m.start() - 64):m.start()])]


def main(argv: list) -> int:
    if len(argv) != 4:
        print("usage: u2c_enclosing.py FILE PATTERN NTH", file=sys.stderr)
        return 2
    with open(argv[1], encoding="utf-8") as f:
        print(enclosing(f.read(), argv[2], int(argv[3])))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
