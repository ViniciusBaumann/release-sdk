#!/usr/bin/env bash
# Contract test for bin/release-spec-lint.js — decision origin + domain-rule floor.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok() { if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); else echo "FAIL: $*"; FAIL=$((FAIL+1)); fi; }
no() { if "$@" >/dev/null 2>&1; then echo "FAIL: expected rejection: $*"; FAIL=$((FAIL+1)); else PASS=$((PASS+1)); fi; }
saysno() { out="$(node "$HERE/release-spec-lint.js" "$1" 2>&1)"; case "$out" in *"$2"*) PASS=$((PASS+1));; *) echo "FAIL: [$1] missing [$2] in: $out"; FAIL=$((FAIL+1));; esac; }

spec() { # <file> <complexity> <status> <decisions...> then rules via RULES env, out via OUT env
  local f="$1" c="$2" st="$3"; shift 3
  { printf -- '---\nphase: 07\ncomplexity: %s\nstatus: %s\n---\n\n# Phase 07\n\n## Outcome\nx\n\n## In scope\n- a\n\n## Out of scope\n%s\n\n## Acceptance criteria\n- [ ] AC-01 x\n\n## Domain rules\n%s\n\n## Decisions\n' "$c" "$st" "${OUT-- nothing else}" "${RULES:-}"
    for d in "$@"; do printf -- '- %s\n' "$d"; done
    printf '\n## Open questions\n- none\n'; } > "$f"
}
R3='- R-01 [USER, invariant] live ETA stays visible
- R-02 [USER] same passage is one row
- R-03 [USER, degraded] no GPS ⇒ show schedule, say so'
R5="$R3"$'\n''- R-04 [USER] holidays follow calendar
- R-05 [USER] terminal departure ≠ stop passage'

echo "── origin tags ──"
RULES="$R3" spec "$TMP/c2-good.md" C2 ready 'D-01 [LOCKED, USER] backend is authority' 'D-02 [LOCK] LOCK-02 tenancy' 'D-03 [CODE: apps/x.py:12] reuse engine'
ok node "$HERE/release-spec-lint.js" "$TMP/c2-good.md"
RULES="$R3" spec "$TMP/untagged.md" C2 ready 'D-01 [LOCKED] backend is authority'
no node "$HERE/release-spec-lint.js" "$TMP/untagged.md"; saysno "$TMP/untagged.md" "no origin tag"
RULES="$R3" spec "$TMP/inferred-ready.md" C2 ready 'D-01 [INFERRED] keep legacy key'
no node "$HERE/release-spec-lint.js" "$TMP/inferred-ready.md"; saysno "$TMP/inferred-ready.md" "INFERRED decision in a status: ready"
RULES="$R3" spec "$TMP/inferred-blocked.md" C2 blocked 'D-01 [INFERRED] keep legacy key'
ok node "$HERE/release-spec-lint.js" "$TMP/inferred-blocked.md"

echo "── domain-rule floor ──"
RULES="$R5" spec "$TMP/c4-good.md" C4 ready 'D-01 [USER] x'
ok node "$HERE/release-spec-lint.js" "$TMP/c4-good.md"
RULES="$R3" spec "$TMP/c4-three.md" C4 ready 'D-01 [USER] x'
no node "$HERE/release-spec-lint.js" "$TMP/c4-three.md"; saysno "$TMP/c4-three.md" "requires ≥5"
RULES='- R-01 [USER] a
- R-02 [USER] b
- R-03 [USER] c' spec "$TMP/no-invariant.md" C2 ready 'D-01 [USER] x'
no node "$HERE/release-spec-lint.js" "$TMP/no-invariant.md"; saysno "$TMP/no-invariant.md" "invariant"
RULES='- R-01 [USER, invariant] a
- R-02 [USER] b
- R-03 [USER] c
- R-04 [USER] d
- R-05 [USER] e' spec "$TMP/no-degraded.md" C3 ready 'D-01 [USER] x'
no node "$HERE/release-spec-lint.js" "$TMP/no-degraded.md"; saysno "$TMP/no-degraded.md" "degraded"
RULES='- R-01 [USER, invariant] a
- R-02 [INFERRED] agent guess
- R-03 [USER] c' spec "$TMP/agent-rule.md" C2 ready 'D-01 [USER] x'
no node "$HERE/release-spec-lint.js" "$TMP/agent-rule.md"; saysno "$TMP/agent-rule.md" "R-02: domain rule not tagged"
RULES="" spec "$TMP/no-rules.md" C2 ready 'D-01 [USER] x'
no node "$HERE/release-spec-lint.js" "$TMP/no-rules.md"
printf -- '---\nphase: 07\ncomplexity: C2\nstatus: ready\n---\n## Decisions\n- D-01 [USER] x\n## Out of scope\n- y\n' > "$TMP/no-section.md"
no node "$HERE/release-spec-lint.js" "$TMP/no-section.md"; saysno "$TMP/no-section.md" 'missing "## Domain rules"'
OUT="" RULES="$R3" spec "$TMP/no-out.md" C2 ready 'D-01 [USER] x'
no node "$HERE/release-spec-lint.js" "$TMP/no-out.md"; saysno "$TMP/no-out.md" "Out of scope"
RULES="" spec "$TMP/c1.md" C1 ready 'D-01 [USER] x'
ok node "$HERE/release-spec-lint.js" "$TMP/c1.md"
no node "$HERE/release-spec-lint.js" "$TMP/does-not-exist.md"
echo "RESULT: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
