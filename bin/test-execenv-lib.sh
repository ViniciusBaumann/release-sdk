#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/release-execenv-lib.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/project"
BARE="$TMP/bare"
mkdir -p "$ROOT/.release-planning" "$ROOT/worktree" "$BARE"

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok: %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf 'FAIL: %s — %s\n' "$1" "$2"; }
eq() { [ "$2" = "$3" ] && ok "$1" || no "$1" "expected [$2], got [$3]"; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) no "$1" "missing [$3] in [$2]" ;; esac; }

echo "── host default ──"
eq "no config uses host" host "$(release_test_harness "$BARE")"
has "host preflight passes" "$(release_execenv_preflight "$BARE")" "EXECENV_PREFLIGHT=ok"
eq "no prefix on host" "" "$(execenv_prefix "$BARE" "$BARE" dev)"
eq "SDK owns zero live environments" 0 "$(release_execenv_max_parallel "$BARE")"

echo "── stable external dev runner ──"
cat > "$ROOT/.release-planning/EXEC-ENV.yml" <<'EOF'
test_harness: external
test_exec_prefix: bash {root}/scripts/dev-test {worktree}
test_timeout: 120
EOF
eq "project config selected" "$ROOT/.release-planning/EXEC-ENV.yml" \
  "$(release_execenv_config "$ROOT")"
eq "external mode selected" external "$(release_test_harness "$ROOT")"
has "external preflight passes" "$(release_execenv_preflight "$ROOT")" "EXECENV_PREFLIGHT=ok"
eq "prefix renders current checkout" "bash $ROOT/scripts/dev-test $ROOT/worktree" \
  "$(execenv_prefix "$ROOT" "$ROOT/worktree" dev)"
eq "configured timeout read" 120 "$(release_test_timeout "$ROOT")"
eq "lifecycle remains inactive" "EXECENV=off" "$(release_execenv_active "$ROOT")"

echo "── lifecycle is fail-safe disabled ──"
cat > "$ROOT/.release-planning/EXEC-ENV.yml" <<'EOF'
test_harness: managed
test_env_provision: touch {worktree}/SHOULD_NOT_EXIST
test_env_teardown: rm -f {worktree}/SHOULD_NOT_EXIST
test_exec_prefix: docker exec app-{label}
EOF
OUT="$(release_execenv_preflight "$ROOT")"
has "managed mode rejected" "$OUT" "EXECENV_ERROR=managed_harness_disabled_use_existing_dev"
eq "direct legacy provision is disabled" "EXECENV_PROVISION=disabled" \
  "$(execenv_provision "$ROOT" "$ROOT/worktree" old)"
[ ! -e "$ROOT/worktree/SHOULD_NOT_EXIST" ] && ok "legacy command was not evaluated" \
  || no "legacy command was not evaluated" "unexpected marker exists"
has "legacy phase prepare fails safely" \
  "$(execenv_phase_prepare "$ROOT" "$ROOT/worktree" old-session)" \
  "EXECENV_PHASE_PREPARE=failed"

echo "── mixed and phase-local configs are rejected/ignored ──"
cat > "$ROOT/.release-planning/EXEC-ENV.yml" <<'EOF'
test_harness: external
test_exec_prefix: bash scripts/dev-test
test_env_provision: docker compose up -d
EOF
has "external lifecycle mix rejected" "$(release_execenv_preflight "$ROOT")" \
  "EXECENV_ERROR=dev_runner_cannot_define_lifecycle_commands"
PHASE="$ROOT/.release-planning/phases/42"
mkdir -p "$PHASE"
printf 'test_harness: managed\ntest_env_provision: docker compose up -d\n' > "$PHASE/EXEC-ENV.yml"
eq "phase override ignored even when env var is set" "$ROOT/.release-planning/EXEC-ENV.yml" \
  "$(RELEASE_PHASE_CONFIG_DIR="$PHASE" release_execenv_config "$ROOT")"

echo "── external compatibility prepare is non-mutating ──"
cat > "$ROOT/.release-planning/EXEC-ENV.yml" <<'EOF'
test_harness: external
test_exec_prefix: bash {root}/scripts/dev-test {worktree}
test_timeout: 0
EOF
OUT="$(execenv_phase_prepare "$ROOT" "$ROOT/worktree" ignored-session)"
has "external prepare succeeds" "$OUT" "EXECENV_PHASE_PREPARE=ok"
has "external prefix returned" "$OUT" "EXECENV_PREFIX=bash $ROOT/scripts/dev-test $ROOT/worktree"
eq "compat teardown is non-mutating" "EXECENV_TEARDOWN=skipped" \
  "$(execenv_phase_teardown "$ROOT" "$ROOT/worktree" dev)"
eq "reuse slots are disabled" "EXECENV_REUSE=off" "$(release_execenv_reuse "$ROOT")"

echo "── bounded test execution ──"
OUT="$(run_test_bounded "$ROOT" 'printf dev-ok' "$ROOT")"
has "passing command returns zero" "$OUT" "TEST_RC=0"
has "passing command is not hung" "$OUT" "TEST_HUNG=false"
OUT_FILE="$(printf '%s\n' "$OUT" | sed -n 's/^TEST_OUTPUT=//p')"
has "captured output is preserved" "$(cat "$OUT_FILE")" "dev-ok"

echo "── worktree safety: the runner must SEE the worktree ──"
rm -f "$ROOT/.release-planning/EXEC-ENV.yml"
eq "host harness ⇒ safe" "WORKTREE_SAFE=yes" "$(release_execenv_worktree_safe "$ROOT")"
printf 'test_harness: external\ntest_exec_prefix: docker exec -w /workspaces/app app-django-1\n' > "$ROOT/.release-planning/EXEC-ENV.yml"
eq "external prefix without {worktree} ⇒ unsafe (tests would hit the main checkout)" \
   "WORKTREE_SAFE=no reason=test_exec_prefix_lacks_{worktree}_placeholder" "$(release_execenv_worktree_safe "$ROOT")"
printf 'test_harness: external\ntest_exec_prefix: docker exec -w /workspaces/{worktree} app-django-1\n' > "$ROOT/.release-planning/EXEC-ENV.yml"
eq "external prefix with {worktree} ⇒ safe" "WORKTREE_SAFE=yes" "$(release_execenv_worktree_safe "$ROOT")"
printf 'test_harness: managed\n' > "$ROOT/.release-planning/EXEC-ENV.yml"
has "managed ⇒ unsafe" "$(release_execenv_worktree_safe "$ROOT")" "WORKTREE_SAFE=no"
rm -f "$ROOT/.release-planning/EXEC-ENV.yml"

echo "── worktree placement + host→runner path mapping (quick tests ITS worktree) ──"
eq "host harness ⇒ sibling worktree" "$ROOT/../release-worktrees/quick/q1" "$(release_execenv_worktree_path "$ROOT" q1)"
printf 'test_harness: external\ntest_exec_prefix: docker exec -w {worktree} -e DB_TEST_NAME=test_{label} app-django-1\ntest_root_in_runner: /workspaces/app\n' > "$ROOT/.release-planning/EXEC-ENV.yml"
eq "external harness ⇒ worktree INSIDE the mounted root" "$ROOT/.release-worktrees/quick/q1" "$(release_execenv_worktree_path "$ROOT" q1)"
mkdir -p "$ROOT/.release-worktrees/quick/q1"
eq "root maps to runner root" "/workspaces/app" "$(release_execenv_runner_path "$ROOT" "$ROOT")"
eq "inner worktree maps to runner path" "/workspaces/app/.release-worktrees/quick/q1" "$(release_execenv_runner_path "$ROOT" "$ROOT/.release-worktrees/quick/q1")"
eq "outside path is left as is" "/elsewhere/wt" "$(release_execenv_runner_path "$ROOT" /elsewhere/wt)"
eq "prefix renders the RUNNER path of the worktree + label" \
   "docker exec -w /workspaces/app/.release-worktrees/quick/q1 -e DB_TEST_NAME=test_q1 app-django-1" \
   "$(execenv_prefix "$ROOT" "$ROOT/.release-worktrees/quick/q1" q1)"
eq "in-place phase renders the runner root" \
   "docker exec -w /workspaces/app -e DB_TEST_NAME=test_dev app-django-1" "$(execenv_prefix "$ROOT" "$ROOT" dev)"
eq "safe with {worktree}" "WORKTREE_SAFE=yes" "$(release_execenv_worktree_safe "$ROOT")"
printf 'test_harness: external\ntest_exec_prefix: bash {root}/scripts/dev-test {worktree}\n' > "$ROOT/.release-planning/EXEC-ENV.yml"
eq "no test_root_in_runner ⇒ host paths unchanged" "bash $ROOT/scripts/dev-test /tmp/wt" "$(execenv_prefix "$ROOT" /tmp/wt dev)"
rm -rf "$ROOT/.release-worktrees" "$ROOT/.release-planning/EXEC-ENV.yml"

echo "── rendering + scheduler compatibility ──"
eq "safe label retained" w1_t02_sess "$(release_execenv_label 'W1/T02 sess')"
eq "render substitutes placeholders" "run /tmp/wt dev $ROOT" \
  "$(release_execenv_render 'run {worktree} {label} {root}' /tmp/wt dev "$ROOT")"
eq "scheduler remains machine bounded" 4 "$(RELEASE_EXEC_CORES=8 release_sched_max_parallel "$ROOT")"

echo ""
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
