#!/usr/bin/env node
// Deterministic contract check for compact phase SPECs, run by /release:plan before the planner.
//
// Why: hubus 133/134 reached `status: ready` with 20-28 decisions of which 0-1 were the user's;
// domain rules (what must keep working, what the user sees when data is missing) were never asked,
// so execute filled them in. This lint makes decision ORIGIN and DOMAIN RULES structural:
//   - every D-XX carries an origin tag: USER | LOCK | CODE:<file:line> | INFERRED
//   - `status: ready` forbids INFERRED decisions
//   - C2+ requires `## Domain rules` with R-XX rules tagged [USER ...]; C2 ≥3 (≥1 invariant),
//     C3/C4 ≥5 (≥1 invariant, ≥1 degraded); `## Out of scope` non-empty
// It never judges prose quality; that stays with spec-clarifier / plan-checker.
const fs = require('fs');

const target = process.argv[2];
if (!target) { process.stderr.write('usage: release-spec-lint.js <SPEC.md>\n'); process.exit(2); }
let text;
try { text = fs.readFileSync(target, 'utf8'); }
catch (error) { process.stderr.write(`SPEC_LINT=FAIL missing=${target}\n`); process.exit(1); }

const findings = [];
const fm = text.match(/^---\s*\n([\s\S]*?)\n---/);
const front = fm ? fm[1] : '';
const field = (k) => { const m = front.match(new RegExp(`^\\s*${k}:\\s*([^#\\n]*)`, 'm')); return m ? m[1].trim() : ''; };
const complexity = (field('complexity').match(/C[0-4]/i) || [''])[0].toUpperCase();
const status = field('status');
const level = complexity ? Number(complexity[1]) : 2; // unknown complexity is treated as C2

const section = (name) => {
  const m = text.match(new RegExp(`^##\\s+${name}\\s*$([\\s\\S]*?)(?=^##\\s|(?![\\s\\S]))`, 'mi'));
  return m ? m[1] : null;
};

// ── decisions: origin tags ────────────────────────────────────────────────────────────────────────
const ORIGIN = /\b(USER|LOCK|CODE\s*:\s*\S+|INFERRED)\b/i;
const decisions = [...text.matchAll(/^\s*-\s*(D-\d+)\s*\[([^\]]*)\]/gm)];
for (const d of decisions) {
  if (!ORIGIN.test(d[2])) findings.push(`${d[1]}: no origin tag (USER | LOCK | CODE:<file:line> | INFERRED)`);
  if (/\bINFERRED\b/i.test(d[2]) && /^ready$/i.test(status)) findings.push(`${d[1]}: INFERRED decision in a status: ready SPEC (confirm with the user or mark it planner discretion)`);
}

// ── domain rules ──────────────────────────────────────────────────────────────────────────────────
if (level >= 2) {
  const rules = section('Domain rules');
  if (rules === null) findings.push(`missing "## Domain rules" section (required for ${complexity || 'C2+'})`);
  else {
    const items = [...rules.matchAll(/^\s*-\s*(R-\d+)\s*\[([^\]]*)\]/gm)];
    const userRules = items.filter(r => /\bUSER\b/i.test(r[2]));
    const kinds = { invariant: 0, degraded: 0 };
    for (const r of userRules) for (const k of Object.keys(kinds)) if (new RegExp(`\\b${k}\\b`, 'i').test(r[2])) kinds[k]++;
    for (const r of items) if (!/\bUSER\b/i.test(r[2])) findings.push(`${r[1]}: domain rule not tagged [USER ...] (rules come from the user, not the agent)`);
    const min = level >= 3 ? 5 : 3;
    if (userRules.length < min) findings.push(`Domain rules: ${userRules.length} [USER] rule(s), ${complexity || 'C2'} requires ≥${min}`);
    if (kinds.invariant < 1) findings.push('Domain rules: no [USER, invariant] rule (what must keep working / never be turned off)');
    if (level >= 3 && kinds.degraded < 1) findings.push('Domain rules: no [USER, degraded] rule (what the user sees when data/GPS/network is missing)');
  }
  const out = section('Out of scope');
  if (out === null || !/^\s*-\s*\S/m.test(out)) findings.push('missing or empty "## Out of scope" section');
}

if (findings.length) {
  process.stdout.write('SPEC_LINT=FAIL\n' + findings.map(x => `- ${x}`).join('\n') + '\n');
  process.exit(1);
}
process.stdout.write(`SPEC_LINT=PASS decisions=${decisions.length} complexity=${complexity || 'unknown'}\n`);
