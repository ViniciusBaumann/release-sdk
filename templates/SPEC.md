<!--
# SPEC.md — Phase {NN}: {phase-slug}
#
# Stack-aware source of truth between ROADMAP and PLAN.
# Produced by /release:spec, completed by /release:plan's decision preflight.
-->

---
phase: {NN}
slug: {phase-slug}
stack: {django | react | fullstack}
created: {YYYY-MM-DDTHH:MM:SSZ}
ambiguity_score: {HIGH | MED | LOW}
status: ready | blocked
maturity: {pre-launch | live}        # optional — copied from PROJECT.md Delivery settings
paired: {/abs/path/other-repo:NN}    # optional — set by /release:spec --paired; read by /release:land --cross
---

# Phase {NN} Spec: {phase-name}

## Goal

{In one paragraph: what observable outcome does this phase deliver, for whom, and how do we know it's done?}

## Stack Detection

- **Detected:** {django | react | fullstack}
- **Signals:** {what files/keywords drove the detection — e.g., "manage.py present, ROADMAP goal mentions 'endpoint'"}
- **LOCK source:** {.release-planning/RELEASE-LOCKS.md or .release-planning/PROJECT.md}
- **Applicable LOCKs:** {LOCK-01, LOCK-02, ...}

## Scope (in)

{Bulleted list of user-observable capabilities delivered by this phase.}

- {Capability 1} — user can {do thing} in {context}
- {Capability 2}
- ...

## Scope (out) — explicit exclusions

{Bulleted list of related things this phase does NOT do. Surfaces scope-creep risk early.}

- {Thing} — deferred to Phase {YY} because {reason}
- {Thing} — not part of this product

## Domain rules

{Business rules in the user's words, ANSWERED BY THE USER (never inferred). `release-spec-lint.js`
requires C2 ≥3 / C3-C4 ≥5, at least one `invariant` and (C3/C4) one `degraded`.}

- R-01 [USER, invariant] {What must keep working / must never be turned off by this phase}
- R-02 [USER, degraded] {What the user sees when data, GPS, network or permission is missing}
- R-03 [USER] {Identity: when are two things the same thing?}
- R-04 [USER] {Precedence: which source wins when they disagree?}
- R-05 [USER] {Boundary: what is explicitly not this phase?}

## Acceptance Criteria

{Measurable, observable assertions a UAT tester would check to declare phase done.}

- [ ] {Specific observable behavior 1}
- [ ] {Specific observable behavior 2}
- [ ] {Behavior whose proof needs data/hosts absent from dev} [external-evidence: {what proves it}]

Every criterion is proven inside the phase by a focused test on the production path. Only evidence
that cannot exist in dev (real captured data, production host clock, physical device) earns the
`[external-evidence: ...]` marker, set here at spec time; the code path is still implemented and
tested, and the verifier reports it as EXTERNAL, never PASS. No criterion is deferred to a
"next slice" during execute.

## Constraints (from LOCKs)

{Non-negotiable boundaries this phase operates within. Map back to LOCK-XX in RELEASE-LOCKS.md / PROJECT.md.}

- LOCK-01: {e.g., Django 5.2 + DRF 3.16}
- LOCK-02: {e.g., Multi-tenant — `empresa_id` scoping}
- {Phase-specific constraint}: {e.g., "Must export 10k rows in <30s"}

## Decisions

{Every decision carries its ORIGIN. `status: ready` forbids `[INFERRED]`.}

- D-01 [USER] {decision — user's answer in one line}
- D-02 [LOCK] {decision — LOCK-XX}
- D-03 [CODE: path/file.py:12] {decision — dominant existing pattern}
- D-04 [INFERRED] {agent proposal awaiting the user's confirmation}

## Open Questions

Questions surfaced by `/release:spec` or the `/release:plan` preflight. Each decision-changing answer
becomes a stable D-XX in this SPEC. Mirror it to CONTEXT.md only when that legacy file already exists.

### HIGH (must resolve before the planner runs)

{Answers fundamentally shape what gets built — scope-defining.}

1. {Question} — options: A {tradeoff}, B {tradeoff}; recommendation: {A or B or "user must decide"}
2. ...

### MED (resolve before planning when architecture, contract, risk or acceptance changes)

{Answers shape UX boundaries or behavior in edge cases.}

1. {Question}
2. ...

### LOW (Claude's discretion acceptable)

{Answers can default to reasonable choice if user shrugs.}

1. {Question} — default if not addressed: {reasonable default}
2. ...

## Ambiguity Score

- **LOW** (0-3 open questions, none decision-changing) — plan can use established patterns.
- **MED** (4-6 open questions, ≤2 HIGH) — plan asks only the decision-changing subset in batches of three.
- **HIGH** (7+ open questions OR ≥3 HIGH) — spec is fuzzy. Consider splitting phase or running `/gsd-explore` first.

**This spec scores: {HIGH | MED | LOW}**

**Justification:** {Why this score — count of HIGH/MED/LOW questions, scope clarity, scope-creep risk.}

{If HIGH:} **Recommendation:** {Split phase into {NN}a/{NN}b, or let `/release:plan` settle the
decision-changing questions before spawning the planner.}

## Next

→ `/release:plan {NN}`  (settle remaining gray areas, lock D-XX, then create an executable PLAN once)

---

_Edit scope via `/release:spec {NN}`. `/release:plan` always performs the final decision preflight
before writing or revising PLAN._
