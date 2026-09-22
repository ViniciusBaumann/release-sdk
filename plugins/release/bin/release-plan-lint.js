#!/usr/bin/env node
// Deterministic structural validation for compact and legacy release plans.
const fs = require('fs');
const path = require('path');

const target = process.argv[2];
if (!target) {
  process.stderr.write('usage: release-plan-lint.js <PLAN.md|PLAN-dir>\n');
  process.exit(2);
}

function markdownFiles(p) {
  const stat = fs.statSync(p);
  if (stat.isFile()) return [p];
  return fs.readdirSync(p).filter(n => n.endsWith('.md')).sort().map(n => path.join(p, n));
}

const findings = [];
const tasks = new Map();
// A verification command must NAME the test that proves the task: a test file path or a node id.
// `verification: true` / `pytest a` let hubus 133 map every AC to a task by ID while the only test
// asserting the live half of the wire never existed. Compact plans fail here; legacy wave plans
// (no `## Acceptance mapping`) keep the old shape-only checks.
const TEST_REF = /(\btests?\/|(^|[\s/])test_[\w-]+\.py|\.test\.[jt]sx?|\.spec\.[jt]sx?|::|--runTestsByPath|-t\s+["']|-k\s+\S)/;
const acceptanceMapping = new Map(); // AC-XX → [T..]
let compact = false;
let files;
try { files = markdownFiles(target); }
catch (error) {
  process.stderr.write(`PLAN_LINT=FAIL missing=${target}\n`);
  process.exit(1);
}

for (const file of files) {
  const text = fs.readFileSync(file, 'utf8');
  const lines = text.split('\n');
  if (lines.length > 600) findings.push(`${file}: plan slice exceeds 600 lines`);
  const mapping = text.match(/^##\s+Acceptance mapping\s*$([\s\S]*?)(?=^##\s|^###\s|(?![\s\S]))/m);
  if (mapping) {
    compact = true;
    for (const m of mapping[1].matchAll(/^\s*-\s*(AC-\d+)\s*(?:→|->|=>|:)\s*(.*)$/gm)) {
      const ids = m[2].split(/[,\s]+/).map(x => x.trim()).filter(x => /^T\d+$/.test(x));
      acceptanceMapping.set(m[1], ids);
      if (ids.length === 0) findings.push(`${file}: ${m[1]} maps to no task`);
    }
    if (acceptanceMapping.size === 0) findings.push(`${file}: Acceptance mapping lists no AC-XX`);
  }
  const headings = [...text.matchAll(/^###\s+(T\d+)\s*(?:[—:-]|$).*$/gm)];
  for (let i = 0; i < headings.length; i++) {
    const id = headings[i][1];
    const start = headings[i].index;
    const end = i + 1 < headings.length ? headings[i + 1].index : text.length;
    const body = text.slice(start, end);
    if (tasks.has(id)) findings.push(`${file}: duplicate task ${id}`);
    const depMatch = body.match(/^\s*-?\s*depends_on:\s*\[([^\]]*)\]/m);
    const deps = depMatch ? depMatch[1].split(',').map(x => x.trim()).filter(Boolean) : [];
    if (!/(^|\n)\s*(?:-\s*)?(?:files?|paths?):/im.test(body)) findings.push(`${file}: ${id} missing files`);
    const verification = body.match(/(^|\n)\s*(?:-\s*)?(?:verify|verification):\s*(.*)/i);
    if (!verification) findings.push(`${file}: ${id} missing verification`);
    else if (!TEST_REF.test(verification[2])) findings.push(`${file}: ${id} verification names no test file or node id`);
    const acceptance = body.match(/^\s*-?\s*acceptance:\s*\[([^\]]*)\]/m);
    const acs = acceptance ? acceptance[1].split(',').map(x => x.trim()).filter(Boolean) : [];
    tasks.set(id, { file, deps, acs, verified: Boolean(verification && TEST_REF.test(verification[2])) });
  }
}

if (tasks.size === 0) findings.push(`${target}: no Txx tasks found`);
if (compact) {
  // Every AC must be claimed by a task (`acceptance: [AC-XX]`) whose verification names a test, and
  // the mapping must agree with the tasks' own claims. Nominal AC→task-ID coverage is not coverage.
  for (const [ac, ids] of acceptanceMapping) {
    for (const id of ids) if (!tasks.has(id)) findings.push(`${target}: ${ac} maps to missing ${id}`);
    const proving = ids.filter(id => tasks.has(id) && tasks.get(id).acs.includes(ac) && tasks.get(id).verified);
    if (proving.length === 0) findings.push(`${target}: ${ac} has no task that claims it in acceptance: and names a test`);
  }
  for (const [id, task] of tasks) {
    if (task.acs.length === 0) findings.push(`${task.file}: ${id} claims no acceptance: [AC-XX]`);
    for (const ac of task.acs) if (!acceptanceMapping.has(ac)) findings.push(`${task.file}: ${id} claims ${ac} absent from Acceptance mapping`);
  }
}
for (const [id, task] of tasks) {
  for (const dep of task.deps) if (!tasks.has(dep)) findings.push(`${task.file}: ${id} depends on missing ${dep}`);
}

const visiting = new Set();
const visited = new Set();
function visit(id, chain = []) {
  if (visiting.has(id)) { findings.push(`${tasks.get(id).file}: dependency cycle ${[...chain, id].join(' -> ')}`); return; }
  if (visited.has(id) || !tasks.has(id)) return;
  visiting.add(id);
  for (const dep of tasks.get(id).deps) visit(dep, [...chain, id]);
  visiting.delete(id); visited.add(id);
}
for (const id of tasks.keys()) visit(id);

if (findings.length) {
  process.stdout.write('PLAN_LINT=FAIL\n' + findings.map(x => `- ${x}`).join('\n') + '\n');
  process.exit(1);
}
process.stdout.write(`PLAN_LINT=PASS tasks=${tasks.size} files=${files.length}\n`);
