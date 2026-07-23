# Review Report Schema

Use this structure for every review.

```markdown
Decision: PASS | PASS_WITH_WARNINGS | REQUIRES_JUSTIFICATION | BLOCK

## Blocking Findings

- Rule: BOUNDARY-001
  Severity: BLOCK
  Location: path/to/file.py::symbol
  Evidence: Concrete observed fact from diff, script output, or code.
  Principle: Project rule or design principle violated.
  Consequence: Why this increases future change cost or risk.
  Smallest remediation: Minimal design correction.
  Confidence: high | medium | low

## Warnings

- Rule: OCP-001
  Severity: WARNING
  Location: path/to/file.py::symbol
  Evidence: Concrete observed fact.
  Consequence: Future change cost.
  Smallest remediation: Minimal correction or justified exception.
  Confidence: high | medium | low

## Open Questions

- Question: What must be clarified before deciding?
  Why it matters: Design consequence.
  Needed evidence: Specific missing file, rule, test, or requirement.

## Passed Invariants

- Rule: DEP-001
  Evidence: No module cycles detected by analyze_imports.py.

## Architecture Change Summary

- Owner module:
- Affected modules:
- Public contracts changed:
- State ownership changed:
- Dependencies added:
- Tests added or changed:

## Recommended Next Action

One concrete next action.
```

Also emit these repair-oriented files when the user asks for a persistent audit
artifact or when reviewing an evidence package created by
`run_governance_review.ps1`:

```text
audit-findings.md
repair-brief.md
```

## audit-findings.md

Group findings by repair priority:

```markdown
# Governance Audit Findings

Decision: PASS | PASS_WITH_WARNINGS | REQUIRES_JUSTIFICATION | BLOCK

## High

- Rule:
  Severity: BLOCK | HIGH
  Location:
  Evidence:
  Why it matters:
  Suggested fix:
  Confidence:

## Medium

- Rule:
  Severity: WARNING | MEDIUM
  Location:
  Evidence:
  Why it matters:
  Suggested fix:
  Confidence:

## Low

- Rule:
  Severity: ADVISORY | LOW
  Location:
  Evidence:
  Suggested fix:
  Confidence:

## Open Questions
```

Use `High` for blockers, security issues, correctness bugs, forbidden
architecture dependencies, and high-confidence issues that should be fixed
before merge.

Use `Medium` for non-blocking design risks, micro-governance findings that
exceed budget, and issues that need a refactor plan.

Use `Low` for advisory cleanup that should not steer the current change unless
the code is already being touched.

## repair-brief.md

Write this file for an AI repair pass:

```markdown
# Repair Brief

## Repair Order

1. Fix High findings first.
2. Fix high-confidence Medium findings next.
3. Leave Low findings unless they are adjacent to required edits.

## Constraints

- Preserve existing behavior.
- Do not broaden public APIs unless required by the finding.
- Keep fixes minimal and localized.
- Add or update boundary, contract, or regression tests.
- Rerun governance review after repair.

## Findings To Fix

- Rule:
  Location:
  Required change:
  Verification:
```

Do not include generic praise or style preferences. Keep the report evidence
first and decision-oriented.
