---
name: software-design-review
description: >
  Review code changes for software design problems using repository architecture
  rules, deterministic structural analysis, and evidence-based semantic review.
  Use after implementing a feature, fixing a bug, refactoring code, optimizing
  code, or before approving a change.
---

# Software Design Review

Review the current code change for architecture and software design quality.

This skill is not a general style review and not an automatic refactoring tool.
Focus on structural design problems that increase future change cost or make
module ownership unclear.

## Required Inputs

Before reviewing, read:

1. The nearest applicable `AGENTS.md`.
2. `architecture/modules.yaml`.
3. `architecture/dependency-rules.yaml`.
4. `architecture/ownership.yaml`.
5. `architecture/exceptions.yaml`, when present.
6. `references/review-rules.yaml`.
7. The current Git diff and changed-file list.
8. The governance evidence package, when available.

If an architecture file does not exist, report the missing governance input.
Do not silently invent project architecture rules.

## Review Scope

Default to reviewing the current Git diff.

Inspect unchanged code only when needed to understand:

- callers and consumers;
- ownership;
- module dependencies;
- existing extension mechanisms;
- duplicated business rules;
- public contracts;
- state persistence.

Do not turn a change review into an unrestricted whole-repository redesign.

## Workflow

### Step 1: Establish Change Intent

Determine:

- requested behavior;
- owner module;
- affected modules;
- added or changed state;
- added or changed public contracts;
- expected extension points;
- implementation constraints.

If change intent is documented in a plan, task, issue, or ADR, use it as the
source of truth. Do not infer a different architecture merely from the
implementation.

### Step 2: Collect Deterministic Evidence

Prefer the one-command governance wrapper when available:

```powershell
.\.agents\skills\software-design-review\scripts\run_governance_review.ps1 `
  -Target <repo> `
  -Background "<change intent>"
```

The wrapper creates an evidence package containing local design evidence,
code-quality-audit output, open-code-review output, and codebase-memory CLI
output when installed.

If the wrapper is unavailable, run the supplied analysis scripts directly:

```bash
python .agents/skills/software-design-review/scripts/collect_diff.py
python .agents/skills/software-design-review/scripts/analyze_imports.py
python .agents/skills/software-design-review/scripts/detect_extension_cost.py
```

Collect:

- changed files;
- added and removed imports;
- cross-module imports;
- private/internal imports;
- dependency cycles;
- changed module count;
- public API changes;
- type-dispatch branches;
- tests added or modified.

Deterministic script output is evidence. Do not replace it with an LLM guess.
Open-code-review comments are advisory evidence, not architecture decisions by
themselves. Code-quality-audit scores and findings are micro-governance signals
unless they map to a hard architecture rule.

### Step 3: Evaluate Hard Architecture Rules

Check:

1. Cross-module code imports only public contracts or facades.
2. No external module imports another module's internal, private, ORM, or
   repository implementation.
3. No new dependency cycle is introduced.
4. A module does not write state owned by another module.
5. High-level domain modules do not depend on infrastructure implementations.
6. Public responses do not expose secrets or private runtime configuration.
7. Public API breaking changes include an explicit migration strategy.

Hard-rule violations must be reported as `BLOCK`.

### Step 4: Review Design Principles

Review only principles supported by concrete evidence. Read
`references/principles.md` when a changed component needs semantic design
judgment.

Use `OPEN_QUESTION` instead of a violation when evidence is insufficient.

### Step 5: Prevent Speculative Findings

Every finding must contain:

- rule ID;
- severity;
- exact file and symbol;
- observed evidence;
- violated project rule or design principle;
- consequence;
- smallest reasonable remediation;
- confidence.

Do not report a violation based only on naming preference, file length, or
personal taste.

### Step 6: Produce The Review Report

Use this order:

1. Decision.
2. Blocking findings.
3. Warnings.
4. Open questions.
5. Passed invariants.
6. Architecture change summary.
7. Recommended next action.

Allowed decisions:

- `PASS`
- `PASS_WITH_WARNINGS`
- `REQUIRES_JUSTIFICATION`
- `BLOCK`

Use the report format in `references/report-schema.md`.

When reviewing an evidence package, also produce repair-oriented artifacts in
the same run directory when possible:

- `audit-findings.md`: High / Medium / Low grouped findings for humans and AI.
- `repair-brief.md`: minimal repair order, constraints, and verification steps.

Do not let raw tool scores decide priority. Map priority from evidence,
architecture rules, consequence, and confidence:

- `High`: blockers, security/correctness bugs, forbidden dependencies,
  ownership violations, or high-confidence issues that should be fixed before
  merge.
- `Medium`: warnings, refactor-plan items, complexity/duplication growth, or
  design risks that need justification.
- `Low`: advisory cleanup that should not steer the current change unless the
  code is already being touched.

## Modification Policy

By default, review only.

Do not modify code unless the user explicitly asks for optimization or repair.

When repair is requested:

1. propose the smallest design correction;
2. identify affected public contracts;
3. preserve behavior;
4. update or add boundary and contract tests;
5. rerun the complete review;
6. report any remaining warning.

## Quality Bar

A useful review must:

- prioritize architecture over formatting;
- distinguish project rules from general recommendations;
- distinguish facts from semantic judgments;
- avoid duplicate findings;
- avoid generic SOLID commentary;
- explain why the issue raises future change cost;
- identify false-positive risks;
- report important rules that passed.

A review that says only "violates SRP" or "consider dependency injection" is
incomplete.
