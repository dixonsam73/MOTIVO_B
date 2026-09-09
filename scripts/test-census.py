#!/usr/bin/env python3
"""C-64 Phase 1 — STRUCTURED TEST CENSUS. Use this instead of grepping logs.

WHY THIS EXISTS. C-64 claimed that tests intermittently failed to execute. That
claim came from counting `Test case '...'` lines in xcodebuild console output,
and it was WRONG: console text does not enumerate every test reliably — the suite
mixes XCTest and swift-testing, and parallel runs present results per clone.
Six structured runs (3 parallel, 3 serial) each reported 118 of 118 declared
tests, all passed, nothing missing.

USE:
    xcodebuild test ... -resultBundlePath run1.xcresult
    python3 scripts/test-census.py run1.xcresult run2.xcresult ...

It reports, per bundle, every test case xcresulttool knows about and its outcome,
and checks declared-vs-executed membership per suite. NEVER infer a test's
absence from console output again.
"""
import json, subprocess, sys, re, io, os, glob

def declared():
    """Every declared test, from source: XCTest `func test…` + swift-testing @Test."""
    out = {}
    for path in glob.glob('MOTIVOTests/*.swift'):
        src = io.open(path, encoding='utf-8').read()
        # XCTest classes
        for m in re.finditer(r'(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase\s*\{', src):
            start = m.end()
            nxt = re.search(r'\n(?:@\w+\s*\n)?(?:final\s+)?class\s+\w+\s*:\s*XCTestCase\s*\{', src[start:])
            body = src[start:start + (nxt.start() if nxt else len(src) - start)]
            for t in re.findall(r'func\s+(test\w*)\s*\(', body):
                out.setdefault(m.group(1), set()).add(t)
        # swift-testing
        for m in re.finditer(r'@Test[^\n]*\n\s*(?:func\s+(\w+))', src):
            out.setdefault('swift-testing', set()).add(m.group(1))
    return out

def executed(bundle):
    """Every test node xcresulttool reports, with its outcome."""
    j = json.loads(subprocess.run(
        ['xcrun','xcresulttool','get','test-results','tests','--path',bundle,'--format','json'],
        capture_output=True, text=True).stdout)
    res = {}
    def walk(n, suite=None):
        if isinstance(n, dict):
            nt = n.get('nodeType'); name = n.get('name','')
            if nt == 'Test Suite': suite = name
            if nt == 'Test Case':
                res[f"{suite}.{name}"] = n.get('result','?')
            for v in n.values(): walk(v, suite)
        elif isinstance(n, list):
            for i in n: walk(i, suite)
    walk(j)
    return res

if __name__ == '__main__':
    d = declared()
    total = sum(len(v) for v in d.values())
    print(f"DECLARED: {total} tests across {len(d)} groups")
    rows = []
    for b in sorted(sys.argv[1:]):
        e = executed(b)
        outcomes = {}
        for k, v in e.items(): outcomes[v] = outcomes.get(v, 0) + 1
        rows.append((os.path.basename(b), len(e), outcomes, set(k.split('.')[-1].rstrip('()') for k in e)))
        print(f"\n{os.path.basename(b)}: reported {len(e)} test cases  {outcomes}")
    # membership check for the named suites
    print("\n--- DECLARED-vs-EXECUTED for the named suites ---")
    for suite in ['AgeBandRecoveryGateTests','SessionRefreshPolicyTests','SharedOnlyUploadTests']:
        decl = d.get(suite, set())
        print(f"\n{suite}: {len(decl)} declared")
        for name, n, o, seen in rows:
            missing = sorted(t for t in decl if t not in seen)
            print(f"   {name}: missing={missing if missing else 'none'}")
