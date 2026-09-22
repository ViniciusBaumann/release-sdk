#!/usr/bin/env node
'use strict';
// release-statusline.js — Claude Code status line for release-sdk projects.
//
// Claude Code pipes one JSON document on stdin (model, workspace, context_window, cost,
// rate_limits, worktree, ...) every time something changes; whatever this script prints is the
// status bar. Two rows by default:
//
//   ◆ Opus · high  ▸ hubus  ⎇ feat/134-migracao  ⟡ fase 134 execute T06 6/9 · Veículo de apoio…
//   ctx [██████████░░░░░░░░░░] 48% 96k/200k · $1.23 · 1h12m · 5h 23% · 7d 41% · cache 91%
//
// The release segment reads the project's own `.release-planning/` (newest phase `.progress.json`,
// else the STATE.md cursor, plus `.unit-active` for a quick in flight), so the bar tells you what
// the SDK is doing without asking "status?".
//
// Env knobs: RELEASE_STATUSLINE_LINES=1 (single row), RELEASE_STATUSLINE_NOCOLOR=1.
// Stdlib only; never shells out (the bar re-runs on every event, so it must stay cheap).
const fs = require('fs');
const path = require('path');

const NOCOLOR = process.env.RELEASE_STATUSLINE_NOCOLOR === '1';
const c = (code, s) => (NOCOLOR ? s : `\x1b[${code}m${s}\x1b[0m`);
const dim = (s) => c('2', s);
const bold = (s) => c('1', s);

function readStdin(cb) {
  let raw = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (d) => { raw += d; });
  process.stdin.on('end', () => cb(raw));
}

function safeJson(raw) {
  try { return JSON.parse(raw); } catch { return {}; }
}

function readText(p) {
  try { return fs.readFileSync(p, 'utf8'); } catch { return ''; }
}

// ── git branch without spawning git ──────────────────────────────────────────────────────────────
function gitBranch(dir) {
  let d = dir;
  for (let i = 0; i < 12 && d; i++) {
    const dotGit = path.join(d, '.git');
    let gitDir = '';
    try {
      const st = fs.statSync(dotGit);
      if (st.isDirectory()) gitDir = dotGit;
      else {
        const m = /gitdir:\s*(.+)/.exec(readText(dotGit));
        if (m) gitDir = path.resolve(d, m[1].trim());
      }
    } catch { /* keep climbing */ }
    if (gitDir) {
      const head = readText(path.join(gitDir, 'HEAD')).trim();
      const m = /^ref: refs\/heads\/(.+)$/.exec(head);
      return m ? m[1] : (head ? head.slice(0, 8) : '');
    }
    const parent = path.dirname(d);
    if (parent === d) break;
    d = parent;
  }
  return '';
}

// ── release-sdk segment ──────────────────────────────────────────────────────────────────────────
function planningRoot(dir) {
  let d = dir;
  for (let i = 0; i < 12 && d; i++) {
    const p = path.join(d, '.release-planning');
    try { if (fs.statSync(p).isDirectory()) return p; } catch { /* climb */ }
    const parent = path.dirname(d);
    if (parent === d) break;
    d = parent;
  }
  return '';
}

function newestProgress(root) {
  const phases = path.join(root, 'phases');
  let best = null;
  let entries = [];
  try { entries = fs.readdirSync(phases); } catch { return null; }
  for (const e of entries) {
    const f = path.join(phases, e, '.progress.json');
    try {
      const st = fs.statSync(f);
      if (!best || st.mtimeMs > best.mtimeMs) best = { mtimeMs: st.mtimeMs, file: f };
    } catch { /* no progress here */ }
  }
  if (!best) return null;
  // A progress file older than a day is a leftover, not live work.
  if (Date.now() - best.mtimeMs > 24 * 3600 * 1000) return null;
  const j = safeJson(readText(best.file));
  return Object.keys(j).length ? j : null;
}

function stateCursor(root) {
  const txt = readText(path.join(root, 'STATE.md'));
  if (!txt) return '';
  const phase = /^\s*active_phase:\s*"?([0-9A-Za-z-]+)"?/m.exec(txt);
  const stage = /^\s*active_stage:\s*"?([a-z-]+)"?/m.exec(txt);
  if (phase && phase[1] !== 'null') return `fase ${phase[1]}${stage && stage[1] !== 'null' ? ' ' + stage[1] : ''}`;
  // Imported/legacy cursors carry `phase_NNN_<event>_at` keys; the newest event wins.
  let last = null;
  const re = /^\s*phase_(\d+)_([a-z_]+?)_at:\s*"?([0-9T:\-+]+)"?/gm;
  let m;
  while ((m = re.exec(txt))) {
    if (!last || m[3] > last.at) last = { phase: m[1], event: m[2], at: m[3] };
  }
  return last ? `fase ${last.phase} ${last.event.replace(/_/g, ' ')}` : '';
}

function releaseSegment(dir) {
  const root = planningRoot(dir);
  if (!root) return '';
  const parts = [];
  const p = newestProgress(root);
  if (p && p.phase) {
    let s = `fase ${p.phase}${p.stage ? ' ' + p.stage : ''}`;
    if (p.task) s += ` ${p.task}`;
    if (p.tasks_done != null && p.tasks_total) s += ` ${p.tasks_done}/${p.tasks_total}`;
    if (p.note) s += ` · ${String(p.note).slice(0, 48)}`;
    parts.push(s);
  } else {
    const s = stateCursor(root);
    if (s) parts.push(s);
  }
  const unit = readText(path.join(root, '.unit-active')).trim();
  if (unit) parts.push(`quick ${unit.split(/\s+/)[0]}`);
  return parts.length ? c('35', '⟡ ' + parts.join(' · ')) : '';
}

// ── formatting helpers ───────────────────────────────────────────────────────────────────────────
function kTokens(n) {
  if (n == null) return '';
  return n >= 1000 ? `${Math.round(n / 1000)}k` : String(n);
}

function duration(ms) {
  if (!ms) return '';
  const m = Math.floor(ms / 60000);
  return m >= 60 ? `${Math.floor(m / 60)}h${String(m % 60).padStart(2, '0')}m` : `${m}m`;
}

function contextBar(cw) {
  if (!cw) return '';
  let pct = cw.used_percentage;
  if (pct == null && cw.context_window_size && cw.current_usage) {
    const u = cw.current_usage;
    const used = (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0);
    pct = Math.round((used / cw.context_window_size) * 100);
  }
  if (pct == null) return '';
  pct = Math.max(0, Math.min(100, Math.round(pct)));
  const width = 20;
  const filled = Math.round((pct / 100) * width);
  const bar = '█'.repeat(filled) + '░'.repeat(width - filled);
  const color = pct >= 80 ? '31' : pct >= 60 ? '33' : '32';
  let s = `ctx ${c(color, `[${bar}] ${pct}%`)}`;
  if (cw.context_window_size && cw.current_usage) {
    const u = cw.current_usage;
    const used = (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0);
    s += ` ${dim(`${kTokens(used)}/${kTokens(cw.context_window_size)}`)}`;
  }
  return s;
}

function limits(rl) {
  if (!rl) return [];
  const out = [];
  const tag = (label, v) => {
    if (!v || v.used_percentage == null) return;
    const p = Math.round(v.used_percentage);
    out.push(`${label} ${c(p >= 90 ? '31' : p >= 70 ? '33' : '2', `${p}%`)}`);
  };
  tag('5h', rl.five_hour);
  tag('7d', rl.seven_day);
  return out;
}

function render(j) {
  const ws = j.workspace || {};
  const cwd = ws.current_dir || j.cwd || process.cwd();
  const projectName = path.basename(ws.project_dir || cwd);

  const head = [];
  const model = (j.model && j.model.display_name) || '';
  if (model) {
    let m = `◆ ${bold(model)}`;
    if (j.effort && j.effort.level) m += dim(` · ${j.effort.level}`);
    if (j.fast_mode) m += c('36', ' · fast');
    head.push(m);
  }
  head.push(`▸ ${projectName}`);
  const branch = (j.worktree && j.worktree.branch) || gitBranch(cwd);
  if (branch) head.push(c('36', `⎇ ${branch}`));
  if (j.worktree && j.worktree.name) head.push(dim(`wt:${j.worktree.name}`));
  if (j.agent && j.agent.name) head.push(dim(`agent:${j.agent.name}`));
  const rel = releaseSegment(cwd);
  if (rel) head.push(rel);

  const tail = [];
  const bar = contextBar(j.context_window);
  if (bar) tail.push(bar);
  if (j.cost && j.cost.total_cost_usd != null) tail.push(`$${j.cost.total_cost_usd.toFixed(2)}`);
  if (j.cost && j.cost.total_duration_ms) tail.push(duration(j.cost.total_duration_ms));
  tail.push(...limits(j.rate_limits));
  if (j.prompt_cache && j.prompt_cache.hit_ratio != null) {
    const h = Math.round(j.prompt_cache.hit_ratio * 100);
    tail.push(`cache ${c(h < 60 ? '33' : '2', `${h}%`)}`);
  }
  if (j.exceeds_200k_tokens) tail.push(c('31', '>200k'));

  const sep = dim('  ');
  if (process.env.RELEASE_STATUSLINE_LINES === '1') return head.concat(tail).join(sep) + '\n';
  return head.join(sep) + '\n' + tail.join(dim(' · ')) + '\n';
}

if (require.main === module) {
  readStdin((raw) => {
    try { process.stdout.write(render(safeJson(raw))); }
    catch (e) { process.stdout.write(`release-sdk statusline: ${e.message}\n`); }
  });
}

module.exports = { render, contextBar, gitBranch, releaseSegment };
