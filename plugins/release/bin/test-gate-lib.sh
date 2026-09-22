#!/usr/bin/env bash
# Contract test for the objective verification GATE (v0.18.0).
#
# SOURCES the real shipped engine — bin/release-gate-lib.sh — so there is NO faithful-slice drift:
# the code under test IS the code skills/{loop,execute,quick} + agents/code-fixer run.
#
# Coverage:
#   #1  stack detection: django (manage.py), react (package.json react), fullstack, unknown
#   #2  default gate is used when no VERIFY-GATE.yml present (django default mentions ruff + pytest)
#   #3  VERIFY-GATE.yml overrides the default; comments + blank lines ignored; order preserved
#   #4  all steps exit 0 → GATE=GREEN, one PASS line per step, no evidence file
#   #5  a step exits non-zero → GATE=RED + GATE_EVIDENCE file with the failing command's output
#   #6  fail-fast (default): stops at the first red step; later steps NOT run
#   #7  GATE_FAILFAST=0: every step runs even after a red
#   #8  first-colon split: a command containing a colon runs intact
#   #9  unknown stack + no config → empty `GATE=` verdict (caller decides)
#   #14 phase-local gate config cannot override the project dev gate
#   #15 every step announces itself and honors EXEC-ENV test_timeout
#   #16 successful steps survive a later RED and are reused on an unchanged tree
#   #17 stable project dev prefix is applied by the gate
#   #19 gate audit: whitelist / missing {focused} / --create-db / per-phase gate copies ⇒ GATE_WARN
#
# Run: bash bin/test-gate-lib.sh
set -euo pipefail

# ${BASH_SOURCE[0]:-$0}: this suite must be runnable under zsh too — the libs are
# SOURCED by a zsh harness in production, and bash-only path resolution hid a real bug.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=release-gate-lib.sh
source "$HERE/release-gate-lib.sh"

PASS=0; FAIL=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  \033[31m✗ %s\033[0m\n      %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
eq() { [ "$2" = "$3" ] && ok "$1" || no "$1" "expected [$2] got [$3]"; }
has() { case "$2" in *"$3"*) ok "$1";; *) no "$1" "missing [$3] in: $2";; esac; }
hasnt() { case "$2" in *"$3"*) no "$1" "unexpected [$3] in: $2";; *) ok "$1";; esac; }

SBX="$(mktemp -d)"; trap 'rm -rf "$SBX"' EXIT

# verdict() — echo just the terminal GATE= value from a run_gate output blob
verdict() { printf '%s\n' "$1" | sed -n 's/^GATE=//p' | tail -1; }

# ══════════════════════════════════════════════════════════════════════════════════════════════════
echo "── #1 stack detection ──"
DJ="$SBX/dj"; mkdir -p "$DJ"; : > "$DJ/manage.py"
eq "manage.py → django" "django" "$(release_detect_stack "$DJ")"
RC="$SBX/rc"; mkdir -p "$RC"; printf '{"dependencies":{"react":"18"}}\n' > "$RC/package.json"
eq "package.json react → react" "react" "$(release_detect_stack "$RC")"
FS="$SBX/fs"; mkdir -p "$FS/backend" "$FS/frontend"; : > "$FS/backend/manage.py"
printf '{"dependencies":{"react":"18"}}\n' > "$FS/frontend/package.json"
eq "backend/manage.py + frontend react → fullstack" "fullstack" "$(release_detect_stack "$FS")"
UN="$SBX/un"; mkdir -p "$UN"
eq "empty dir → unknown" "unknown" "$(release_detect_stack "$UN")"

echo "── #2 default gate used when no config (django) ──"
DEF="$(release_resolve_gate "$DJ")"
has "django default mentions ruff" "$DEF" "ruff"
has "django default mentions pytest" "$DEF" "pytest"
has "django default mentions makemigrations" "$DEF" "makemigrations"

echo "── #3 VERIFY-GATE.yml overrides default + ignores comments/blanks, keeps order ──"
CFG="$SBX/cfg"; mkdir -p "$CFG/.release-planning"
cat > "$CFG/.release-planning/VERIFY-GATE.yml" <<'YML'
# project gate
lint: true

test: true
YML
RES="$(release_resolve_gate "$CFG")"
hasnt "default NOT used when config present (no ruff)" "$RES" "ruff"
has "config step lint present" "$RES" "lint: true"
has "config step test present" "$RES" "test: true"
hasnt "comment line dropped" "$RES" "project gate"
eq "blank lines dropped (2 real steps)" "2" "$(printf '%s\n' "$RES" | grep -c .)"

echo "── #4 all green → GATE=GREEN, PASS per step, no evidence ──"
GRN="$SBX/grn"; mkdir -p "$GRN/.release-planning"
printf 'lint: true\ntest: true\n' > "$GRN/.release-planning/VERIFY-GATE.yml"
OUT="$(run_gate "$GRN")"
eq "verdict GREEN" "GREEN" "$(verdict "$OUT")"
has "lint PASS" "$OUT" "GATE_STEP=lint PASS"
has "test PASS" "$OUT" "GATE_STEP=test PASS"
hasnt "no evidence on green" "$OUT" "GATE_EVIDENCE="

echo "── #5 a red step → GATE=RED + evidence file with the failing output ──"
RED="$SBX/red"; mkdir -p "$RED/.release-planning"
cat > "$RED/.release-planning/VERIFY-GATE.yml" <<'YML'
lint: true
test: sh -c 'echo BOOM-FAILURE >&2; exit 7'
YML
OUT="$(run_gate "$RED")"
eq "verdict RED" "RED" "$(verdict "$OUT")"
has "test FAIL" "$OUT" "GATE_STEP=test FAIL"
EV="$(printf '%s\n' "$OUT" | sed -n 's/^GATE_EVIDENCE=//p' | head -1)"
{ [ -n "$EV" ] && [ -f "$EV" ]; } && ok "evidence file created" || no "no evidence file" "$EV"
has "evidence captures the failing output" "$(cat "$EV" 2>/dev/null)" "BOOM-FAILURE"
has "evidence records the exit code" "$(cat "$EV" 2>/dev/null)" "exit: 7"

echo "── #6 fail-fast (default): stop at first red, later step not run ──"
FF="$SBX/ff"; mkdir -p "$FF/.release-planning"
printf 'a: false\nb: true\n' > "$FF/.release-planning/VERIFY-GATE.yml"
OUT="$(run_gate "$FF")"
has "step a ran (FAIL)" "$OUT" "GATE_STEP=a FAIL"
hasnt "step b NOT run (fail-fast)" "$OUT" "GATE_STEP=b"
eq "fail-fast verdict RED" "RED" "$(verdict "$OUT")"

echo "── #7 GATE_FAILFAST=0: run every step despite a red ──"
OUT="$(GATE_FAILFAST=0 run_gate "$FF")"
has "step a ran" "$OUT" "GATE_STEP=a FAIL"
has "step b ALSO ran (no fail-fast)" "$OUT" "GATE_STEP=b PASS"
eq "no-failfast verdict still RED" "RED" "$(verdict "$OUT")"

echo "── #8 first-colon split: command containing a colon runs intact ──"
COL="$SBX/col"; mkdir -p "$COL/.release-planning"
printf 'unit: sh -c "echo a:b:c"\n' > "$COL/.release-planning/VERIFY-GATE.yml"
OUT="$(run_gate "$COL")"
eq "colon-in-command → GREEN" "GREEN" "$(verdict "$OUT")"
has "step name parsed as 'unit'" "$OUT" "GATE_STEP=unit PASS"

echo "── #9 unknown stack + no config → empty verdict ──"
OUT="$(run_gate "$UN")"
eq "empty verdict when nothing resolves" "" "$(verdict "$OUT")"

echo "── #11 baseline bridge: inherited failures do not turn the gate RED (v0.23.0) ──"
BR="$SBX/baseline-proj"; mkdir -p "$BR/.release-planning"
cat > "$BR/.release-planning/test-baselines.json" <<'JSON'
{ "suites": { "test": { "failures": [
  {"id": "apps/financeiro/tests/test_dre.py::test_saldo", "error": "AssertionError"}
] } } }
JSON
# a step that fails with ONLY the known failure
cat > "$BR/.release-planning/VERIFY-GATE.yml" <<'YML'
test: printf 'FAILED apps/financeiro/tests/test_dre.py::test_saldo - AssertionError: 1 != 2\n1 failed\n'; exit 1
YML
OUT="$(run_gate "$BR")"
has "known-only failure → PASS_BASELINE" "$OUT" "GATE_STEP=test PASS_BASELINE"
eq  "gate stays GREEN (inherited reds are not this phase's regressions)" "GATE=GREEN" "$(printf '%s\n' "$OUT" | grep '^GATE=')"

# same step, plus ONE unknown failure
cat > "$BR/.release-planning/VERIFY-GATE.yml" <<'YML'
test: printf 'FAILED apps/financeiro/tests/test_dre.py::test_saldo - AssertionError: 1 != 2\nFAILED apps/novo/tests/test_new.py::test_regression - TypeError: boom\n2 failed\n'; exit 1
YML
OUT="$(run_gate "$BR")"
has "one unknown failure → plain FAIL" "$OUT" "GATE_STEP=test FAIL"
eq  "gate RED" "GATE=RED" "$(printf '%s\n' "$OUT" | grep '^GATE=')"
has "evidence still captured for the maker" "$OUT" "GATE_EVIDENCE="

# same known failure, but a DIFFERENT error type → not the same signature
cat > "$BR/.release-planning/VERIFY-GATE.yml" <<'YML'
test: printf 'FAILED apps/financeiro/tests/test_dre.py::test_saldo - IntegrityError: dup\n1 failed\n'; exit 1
YML
eq "same test, different error → RED (a new bug behind an old red)" "GATE=RED" \
   "$(run_gate "$BR" | grep '^GATE=')"

# no baseline file at all → never soften a RED
rm -f "$BR/.release-planning/test-baselines.json"
cat > "$BR/.release-planning/VERIFY-GATE.yml" <<'YML'
test: printf 'FAILED apps/financeiro/tests/test_dre.py::test_saldo - AssertionError: 1 != 2\n'; exit 1
YML
eq "no baseline file → RED (fail-safe)" "GATE=RED" "$(run_gate "$BR" | grep '^GATE=')"

echo "── #12 quick gate skips broad tests ──"
Q="$SBX/quick"; mkdir -p "$Q"; touch "$Q/manage.py"
OUT="$(release_resolve_quick_gate "$Q")"
has "quick keeps lint" "$OUT" "ruff check"
has "quick keeps migration drift" "$OUT" "makemigrations --check"
hasnt "quick omits the broad suite" "$OUT" "pytest . -q"
has "quick re-runs the diff-implied focused tests" "$OUT" "pytest {focused}"

echo "── #19 gate audit: a hand whitelist / per-phase gate copy is warned about, never hidden ──"
GA="$SBX/audit"; mkdir -p "$GA/.release-planning/phases/07-x"; touch "$GA/manage.py"
printf 'lint: true\ntest-rls: pytest apps/core/tests/test_rls_a.py apps/core/tests/test_rls_b.py -q --create-db\n' > "$GA/.release-planning/VERIFY-GATE.yml"
touch "$GA/.release-planning/phases/07-x/07-VERIFY-GATE.yml"
OUT="$(release_gate_audit "$GA")"
has "whitelist of test files ⇒ no-broad-step" "$OUT" "GATE_WARN=no-broad-step"
has "no {focused} ⇒ no-focused-step" "$OUT" "GATE_WARN=no-focused-step"
has "--create-db in a step is flagged" "$OUT" "GATE_WARN=create-db step=test-rls"
has "per-phase gate copy in an unfinished phase is flagged" "$OUT" "GATE_WARN=phase-local-gate"
touch "$GA/.release-planning/phases/07-x/07-SUMMARY.md"
hasnt "archived copy of a finished phase is history, not drift" "$(release_gate_audit "$GA")" "phase-local-gate"
rm "$GA/.release-planning/phases/07-x/07-SUMMARY.md"
OUT="$(run_gate "$GA" 2>/dev/null)"
has "run_gate surfaces the audit" "$OUT" "GATE_WARN=no-broad-step"
rm "$GA/.release-planning/VERIFY-GATE.yml" "$GA/.release-planning/phases/07-x/07-VERIFY-GATE.yml"
OUT="$(release_gate_audit "$GA")"
hasnt "django default gate has a broad step" "$OUT" "no-broad-step"
hasnt "django default gate has a {focused} step" "$OUT" "no-focused-step"
hasnt "no per-phase copies ⇒ no warning" "$OUT" "phase-local-gate"

echo "── #13 GREEN cache is keyed by committed tree + commands ──"
C="$SBX/cache"; mkdir -p "$C/.release-planning"; git -C "$C" init -q
git -C "$C" config user.email test@example.com; git -C "$C" config user.name Test
printf 'ok\n' > "$C/tracked.txt"; git -C "$C" add tracked.txt; git -C "$C" commit -qm init
printf 'check: true\n' > "$C/.release-planning/VERIFY-GATE.yml"
OUT="$(run_gate_cached "$C")"
has "first run green" "$OUT" "GATE=GREEN"
OUT="$(run_gate_cached "$C")"
has "second run cache hit" "$OUT" "GATE_CACHE=hit"
printf 'dirty\n' >> "$C/tracked.txt"
OUT="$(run_gate_cached "$C")"
hasnt "dirty tree never reuses cache" "$OUT" "GATE_CACHE=hit"

echo "── #14 project gate remains authoritative ──"
PG="$SBX/phase-gate"; mkdir -p "$PG/.release-planning/phases/42-fast-gate"
printf 'global: true\n' > "$PG/.release-planning/VERIFY-GATE.yml"
printf 'phase: false\n' > "$PG/.release-planning/phases/42-fast-gate/VERIFY-GATE.yml"
OUT="$(RELEASE_PHASE_CONFIG_DIR="$PG/.release-planning/phases/42-fast-gate" run_gate "$PG")"
has "project gate selected" "$OUT" "GATE_STEP=global PASS"
hasnt "phase-local gate ignored" "$OUT" "GATE_STEP=phase"

echo "── #15 observable + bounded steps ──"
BD="$SBX/bounded"; mkdir -p "$BD/.release-planning"
printf 'test_harness: host\ntest_timeout: 1\n' > "$BD/.release-planning/EXEC-ENV.yml"
printf 'slow: sleep 5\n' > "$BD/.release-planning/VERIFY-GATE.yml"
if [ "$(release_timeout_available 1)" = yes ]; then
  OUT="$(run_gate "$BD")"
  has "step start is observable before its verdict" "$OUT" "GATE_STEP_START=slow"
  has "timeout is a distinct gate result" "$OUT" "GATE_STEP=slow TIMEOUT"
  eq "timeout turns the gate RED" "RED" "$(verdict "$OUT")"
else
  ok "bounded gate timeout skipped (no timeout binary on this host)"
fi

echo "── #16 per-step GREEN cache after a later RED ──"
SCROOT="$SBX/step-cache"; MARKS="$SBX/step-cache-marks"
mkdir -p "$SCROOT/.release-planning" "$MARKS"; git -C "$SCROOT" init -q
git -C "$SCROOT" config user.email test@example.com; git -C "$SCROOT" config user.name Test
printf 'tracked\n' > "$SCROOT/tracked.txt"; git -C "$SCROOT" add tracked.txt; git -C "$SCROOT" commit -qm init
cat > "$SCROOT/.release-planning/VERIFY-GATE.yml" <<YML
cheap: printf x >> '$MARKS/cheap'
late: false
YML
OUT="$(run_gate "$SCROOT")"
has "cheap step passed before late RED" "$OUT" "GATE_STEP=cheap PASS"
OUT="$(run_gate "$SCROOT")"
has "unchanged cheap step reused" "$OUT" "GATE_STEP=cheap PASS_CACHED"
eq "cached step did not execute twice" "1" "$(wc -c < "$MARKS/cheap" | tr -d ' ')"

echo "── #17 stable project dev prefix ──"
DP="$SBX/dev-prefix"; mkdir -p "$DP/.release-planning"
printf 'test_harness: external\ntest_exec_prefix: env RELEASE_DEV_RUNNER=active\n' \
  > "$DP/.release-planning/EXEC-ENV.yml"
printf '%s\n' "dev: python3 -c 'import os; assert os.environ[\"RELEASE_DEV_RUNNER\"] == \"active\"'" \
  > "$DP/.release-planning/VERIFY-GATE.yml"
PREFIX="$(execenv_prefix "$DP" "$DP" dev)"
OUT="$(RELEASE_EXEC_PREFIX="$PREFIX" run_gate "$DP")"
has "project prefix applied automatically" "$OUT" "GATE_STEP=dev PASS"

echo "── #18 {focused}: impact-scoped targets from the diff; no targets ⇒ SKIPPED, never RED ──"
FO="$SBX/focused"; mkdir -p "$FO/backend/apps/publico/tests" "$FO/backend/apps/core" "$FO/src/features/x" "$FO/.release-planning"
git -C "$FO" init -q -b main; git -C "$FO" config user.email t@t; git -C "$FO" config user.name t
: > "$FO/backend/apps/publico/tests/test_a.py"; : > "$FO/backend/apps/core/tests.py"; : > "$FO/backend/apps/core/models.py"
: > "$FO/src/features/x/hook.ts"; : > "$FO/src/features/x/hook.test.ts"; : > "$FO/README.md"
printf '.release-planning/\n' > "$FO/.gitignore"
git -C "$FO" add -A; git -C "$FO" commit -qm base
git -C "$FO" checkout -q -b feat/1
printf 'x' > "$FO/backend/apps/publico/previsao.py"; printf 'y' > "$FO/backend/apps/core/models.py"; printf 'z' > "$FO/src/features/x/hook.ts"
git -C "$FO" add -A; git -C "$FO" commit -qm change
eq "targets: publico tests dir + core tests.py + sibling RN test" \
   "backend/apps/core/tests.py backend/apps/publico/tests src/features/x/hook.test.ts" \
   "$(release_focused_test_targets "$FO")"
eq "base ref auto-detected as main" "main" "$(release_gate_base_ref "$FO")"
eq "RELEASE_GATE_BASE wins" "feat/1" "$(RELEASE_GATE_BASE=feat/1 release_gate_base_ref "$FO")"
eq "same tree as base ⇒ no targets" "" "$(RELEASE_GATE_BASE=feat/1 release_focused_test_targets "$FO")"
printf 'test-focused: echo RUN {focused}\n' > "$FO/.release-planning/VERIFY-GATE.yml"
OUT="$(run_gate "$FO")"
has "placeholder substituted in the step" "$OUT" "GATE_STEP=test-focused PASS"
eq "gate GREEN" "GREEN" "$(verdict "$OUT")"
printf 'q' > "$FO/README.md"; git -C "$FO" add -A; git -C "$FO" commit -qm docs
git -C "$FO" checkout -q -b docs-only main; printf 'r' > "$FO/README.md"; git -C "$FO" add -A; git -C "$FO" commit -qm docs2
OUT="$(run_gate "$FO")"
has "diff without test-bearing files ⇒ SKIPPED_NO_TARGETS" "$OUT" "GATE_STEP=test-focused SKIPPED_NO_TARGETS"
eq "skipped step never turns the gate RED" "GREEN" "$(verdict "$OUT")"
printf 'feat/1\n' > "$FO/.release-planning/.gate-base"
eq ".gate-base file is honored" "feat/1" "$(release_gate_base_ref "$FO")"

echo ""
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
