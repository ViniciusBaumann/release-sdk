#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok() { if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); else echo "FAIL: $1"; FAIL=$((FAIL+1)); fi; }
no() { if "$@" >/dev/null 2>&1; then echo "FAIL: expected rejection: $1"; FAIL=$((FAIL+1)); else PASS=$((PASS+1)); fi; }

printf '%s\n' '# Plan' '### T01 — test' '- files: [tests/test_x.py]' '- depends_on: []' '- verification: pytest tests/test_x.py' '### T02 — implement' '- files: [app/x.py]' '- depends_on: [T01]' '- verification: pytest tests/test_x.py' > "$TMP/good.md"
ok node "$HERE/release-plan-lint.js" "$TMP/good.md"
printf '%s\n' '# Plan' '### T01 — broken' '- depends_on: [T99]' > "$TMP/missing.md"
no node "$HERE/release-plan-lint.js" "$TMP/missing.md"
printf '%s\n' '# Plan' '### T01 — a' '- files: [a]' '- depends_on: [T02]' '- verification: true' '### T02 — b' '- files: [b]' '- depends_on: [T01]' '- verification: true' > "$TMP/cycle.md"
no node "$HERE/release-plan-lint.js" "$TMP/cycle.md"
printf '%s\n' '# Plan' '### T01 — simple' '- files: [a]' '- depends_on: []' '- verification: pytest tests/test_a.py' > "$TMP/no-harness.md"
ok node "$HERE/release-plan-lint.js" "$TMP/no-harness.md"
# verification must NAME a test (file path or node id) — `true` / bare `pytest a` no longer pass
printf '%s\n' '# Plan' '### T01 — vague' '- files: [a]' '- depends_on: []' '- verification: pytest a' > "$TMP/vague.md"
no node "$HERE/release-plan-lint.js" "$TMP/vague.md"
printf '%s\n' '# Plan' '### T01 — nodeid' '- files: [a]' '- depends_on: []' '- verification: pytest apps/x/tests.py::test_wire_emits_live' > "$TMP/nodeid.md"
ok node "$HERE/release-plan-lint.js" "$TMP/nodeid.md"
printf '%s\n' '# Plan' '### T01 — vitest' '- files: [a]' '- depends_on: []' '- verification: npx vitest run src/x.test.tsx' > "$TMP/vitest.md"
ok node "$HERE/release-plan-lint.js" "$TMP/vitest.md"
# compact plans: every AC in the mapping needs a task that claims it AND names a test; claims must agree
printf '%s\n' '# Plan' '## Acceptance mapping' '- AC-01 → T01' '- AC-02 → T01, T02' '' '### T01 — a' '- files: [a]' '- depends_on: []' '- acceptance: [AC-01, AC-02]' '- verification: pytest tests/test_a.py' '### T02 — b' '- files: [b]' '- depends_on: [T01]' '- acceptance: [AC-02]' '- verification: pytest tests/test_b.py::test_b' > "$TMP/ac-good.md"
ok node "$HERE/release-plan-lint.js" "$TMP/ac-good.md"
printf '%s\n' '# Plan' '## Acceptance mapping' '- AC-01 → T01' '- AC-02 → T02' '' '### T01 — a' '- files: [a]' '- depends_on: []' '- acceptance: [AC-01]' '- verification: pytest tests/test_a.py' '### T02 — b' '- files: [b]' '- depends_on: []' '- acceptance: [AC-01]' '- verification: pytest tests/test_b.py' > "$TMP/ac-unclaimed.md"
no node "$HERE/release-plan-lint.js" "$TMP/ac-unclaimed.md"
printf '%s\n' '# Plan' '## Acceptance mapping' '- AC-01 → T01' '' '### T01 — a' '- files: [a]' '- depends_on: []' '- acceptance: [AC-01]' '- verification: manual check' > "$TMP/ac-untested.md"
no node "$HERE/release-plan-lint.js" "$TMP/ac-untested.md"
printf '%s\n' '# Plan' '## Acceptance mapping' '- AC-01 → T09' '' '### T01 — a' '- files: [a]' '- depends_on: []' '- acceptance: [AC-01]' '- verification: pytest tests/test_a.py' > "$TMP/ac-missing-task.md"
no node "$HERE/release-plan-lint.js" "$TMP/ac-missing-task.md"
printf '%s\n' '# Plan' '## Acceptance mapping' '- AC-01 → T01' '' '### T01 — a' '- files: [a]' '- depends_on: []' '- acceptance: [AC-01, AC-07]' '- verification: pytest tests/test_a.py' > "$TMP/ac-phantom.md"
no node "$HERE/release-plan-lint.js" "$TMP/ac-phantom.md"
echo "RESULT: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
