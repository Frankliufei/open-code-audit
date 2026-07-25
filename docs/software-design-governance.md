# Software Design Governance Skill Design

## Goal

Build `software-design-review` as an executable and auditable skill, not a
generic code-optimization prompt.

The skill should convert software design opinions into a repeatable governance
workflow:

```text
Architecture rules
  -> deterministic evidence collection
  -> evidence-based LLM review
  -> structured report
  -> optional repair only when requested
```

## Core Idea

A useful design-review skill needs four layers:

1. Rules are configurable.
2. Facts are collected deterministically.
3. Judgments are traceable.
4. Results are reported in a stable format.

## Governance Layers

The software design governance system is split into two layers:

```text
Architecture governance
  -> module boundaries
  -> dependency direction
  -> state ownership
  -> public/private contracts
  -> architectural exceptions

Micro design governance
  -> local code smells
  -> function/class complexity
  -> duplication
  -> naming clarity
  -> API ergonomics
  -> testability
  -> maintainability trend
```

### Architecture Governance

Architecture governance answers:

```text
Is this code allowed to exist in this module?
Is this module allowed to depend on that module?
Is this module allowed to read or write this state?
Is this dependency crossing a public contract or an internal implementation?
Does this change introduce a new architectural exception?
```

Architecture governance should be rule-driven and auditable.

Primary inputs:

```text
architecture/modules.yaml
architecture/ownership.yaml
architecture/dependency-rules.yaml
architecture/exceptions.yaml
```

Primary evidence:

```text
git diff
changed files
import graph
module dependency graph
public/private path classification
state ownership mapping
```

Primary decisions:

```text
PASS
PASS_WITH_WARNINGS
REQUIRES_JUSTIFICATION
BLOCK
```

Architecture governance may block a change when hard rules are violated.

Examples:

```text
BOUNDARY-001: Cross-module private/internal import
DEP-001: Circular module dependency
OWNERSHIP-001: Foreign state ownership write
CONTRACT-001: Breaking public contract without migration path
```

### Micro Design Governance

Micro design governance answers:

```text
Is this local implementation becoming harder to understand?
Did this function/class gain too many responsibilities?
Did complexity increase without justification?
Is business logic duplicated?
Are names and boundaries still clear?
Are tests sufficient for the local behavior?
```

Micro governance should be mostly advisory at first.

Primary inputs:

```text
quality-budget.yaml
code smell scan
complexity metrics
duplication scan
test coverage signal
change frequency
review history
```

Primary decisions:

```text
PASS
PASS_WITH_WARNINGS
REQUIRES_REFACTOR_PLAN
```

Micro governance should not usually block a change by raw score alone.

Bad rule:

```text
score < 80 => BLOCK
```

Better rule:

```text
complexity increased by more than allowed budget
and no test/justification was added
=> REQUIRES_REFACTOR_PLAN
```

### Relationship Between The Two Layers

Architecture governance is the legal system.

Micro design governance is the health check.

Architecture governance says:

```text
This dependency is forbidden.
This state belongs to another module.
This public contract was broken.
```

Micro governance says:

```text
This function is becoming too complex.
This class has multiple reasons to change.
This repeated logic should probably become a shared policy.
```

Use architecture governance as a gate.
Use micro governance as a radar.

### Recommended First Implementation

Implement architecture governance first:

```text
software-design-review
```

Initial hard checks:

```text
1. Cross-module private/internal imports
2. Forbidden dependency directions
3. Circular dependencies
4. State ownership violations
```

Then add micro governance as a second skill or second mode:

```text
code-quality-review
```

Initial advisory checks:

```text
1. Complexity growth
2. Duplication
3. Large function/class growth
4. Too many conditional branches
5. Weak or missing tests around changed behavior
```

Keep the two separate because they have different severity models:

```text
Architecture violation => may BLOCK
Micro smell => usually WARNING or REQUIRES_REFACTOR_PLAN
```

## Layer 1: Rules Are Configurable

Use YAML files to define what is correct for this repository.

Example files:

```text
architecture/modules.yaml
architecture/ownership.yaml
architecture/dependency-rules.yaml
architecture/exceptions.yaml
architecture/quality-budget.yaml
```

These files answer questions such as:

- Which paths belong to which module?
- Which paths are public contracts?
- Which modules may depend on each other?
- Which dependencies are forbidden?
- Which module owns each state, entity, or capability?
- Which legacy violations are temporarily allowed?

Example:

```yaml
version: 1

modules:
  analysis:
    paths:
      - app/analysis/**
    public_paths:
      - app/analysis/public/**
    may_depend_on:
      - core.public
      - data_manager.public
    forbidden_dependencies:
      - platform_manager.internal
```

This turns a vague design preference like "modules should not depend on
internals" into an explicit project rule.

## Layer 2: Facts Are Collected Deterministically

Scripts should not make aesthetic judgments. They should collect facts.

Initial scripts:

```text
.agents/skills/software-design-review/scripts/collect_diff.py
.agents/skills/software-design-review/scripts/analyze_imports.py
.agents/skills/software-design-review/scripts/detect_extension_cost.py
.agents/skills/software-design-review/scripts/check_tools.ps1
.agents/skills/software-design-review/scripts/install_tools.ps1
.agents/skills/software-design-review/scripts/run_governance_review.ps1
```

Example output:

```json
{
  "cross_module_edges": [
    {
      "source": "analysis",
      "target": "platform_manager",
      "file": "app/analysis/service.py",
      "import": "app.modules.platform_manager.internal.registry",
      "target_visibility": "internal",
      "rule": "BOUNDARY-001"
    }
  ]
}
```

The script output becomes evidence. Codex should not replace deterministic
facts with guesses.

### One-Command Evidence Collection

Use `run_governance_review.ps1` as the portable orchestration entry point:

```powershell
& .\.agents\skills\software-design-review\scripts\run_governance_review.ps1 `
  -Target D:\path\to\repo `
  -OutputRoot D:\path\to\repo\.governance `
  -ProjectKey my-project `
  -Background "Business context for this change"
```

The wrapper creates:

```text
.governance/<timestamp>/
├── evidence-summary.json
├── tool-check.json
├── collect-diff.json
├── analyze-imports.json
├── extension-cost.json
├── code-review-graph-status.txt
├── code-quality-audit/
├── open-code-review.txt
└── next-step.md
```

External tools are resolved in this order:

```text
environment variable
project-local node_modules/.bin
global PATH
known local fallback path
```

The skill package should include orchestration scripts and requirements, not
external tool source trees, global npm packages, virtual environments, or large
binaries. See `.agents/skills/software-design-review/references/tool-requirements.md`.

## Layer 3: Judgments Are Traceable

`SKILL.md` should define the review procedure:

```text
1. Read architecture/*.yaml
2. Read the current git diff
3. Run available evidence-collection scripts
4. Evaluate hard architecture rules
5. Review semantic design risks only when supported by evidence
6. Output the report using references/report-schema.md
```

Every finding must include:

```text
rule ID
severity
file and symbol
observed evidence
violated project rule or design principle
consequence
smallest reasonable remediation
confidence
```

Bad finding:

```text
This violates SOLID.
```

Good finding:

```text
Rule: BOUNDARY-001
Severity: BLOCK
File: app/analysis/service.py
Evidence: imports app.modules.platform_manager.internal.registry
Violated rule: analysis cannot depend on platform_manager.internal
Consequence: analysis now depends on provider internals, increasing change coupling
Smallest remediation: expose the required capability through platform_manager public facade
Confidence: high
```

## Layer 4: Reports Are Stable

Use `references/report-schema.md` to force a consistent output.

Suggested format:

```markdown
# Software Design Review Report

Decision: PASS | PASS_WITH_WARNINGS | REQUIRES_JUSTIFICATION | BLOCK

## Blocking Findings

- Rule:
- Severity:
- File:
- Symbol:
- Evidence:
- Violated rule:
- Consequence:
- Smallest remediation:
- Confidence:

## Warnings

## Passed Invariants

## Open Questions

## Architecture Change Summary

## Recommended Next Action
```

This makes reviews comparable, auditable, and easier to approve.

## First Version Scope

The first version should avoid becoming a generic SOLID reviewer.

Focus on four high-value checks:

```text
1. Cross-module private/internal imports
2. Forbidden dependency directions
3. Circular dependencies
4. State ownership violations
```

SRP, OCP, interface segregation, and substitutability should initially be
reported as semantic warnings unless backed by strong project-specific evidence.

## Operating Policy

Default behavior:

```text
review only
```

The skill must not modify code unless the user explicitly asks for optimization
or repair.

When repair is requested:

```text
1. Propose the smallest design correction
2. Identify affected public contracts
3. Preserve behavior
4. Add or update boundary/contract tests
5. Rerun the review
6. Report remaining warnings
```

## Current Files

- `.agents/skills/software-design-review/SKILL.md` defines the review workflow.
- `.agents/skills/software-design-review/references/` contains review
  principles, rule IDs, examples, and report format.
- `.agents/skills/software-design-review/scripts/` contains evidence collection
  scripts and the one-command governance wrapper.
- `architecture/modules.yaml` defines the project module map.
- `architecture/ownership.yaml` defines state and capability ownership.
- `architecture/dependency-rules.yaml` defines hard dependency rules.
- `architecture/exceptions.yaml` records reviewed exceptions.
- `architecture/quality-budget.yaml` defines review thresholds.

## Current Status

This is a starter governance skeleton. The workspace did not expose application
source files when the first version was created, so `architecture/*.yaml` uses
placeholder module names:

- `core`
- `application`
- `domain`
- `infrastructure`

Before treating the review as a release gate, replace those placeholders with
the repository's real modules, paths, public boundaries, ownership rules, and
allowed dependencies.

## First Review Flow

1. Fill `architecture/modules.yaml` with real module paths.
2. Fill `architecture/ownership.yaml` with real state ownership.
3. Run:

   ```bash
   python .agents/skills/software-design-review/scripts/collect_diff.py
   python .agents/skills/software-design-review/scripts/analyze_imports.py
   python .agents/skills/software-design-review/scripts/detect_extension_cost.py
   ```

4. Use `$software-design-review` to produce the final structured review.
5. Convert accurate repeated findings into architecture tests or stricter rules.

## Summary

The governance model is:

```text
YAML defines what is correct.
Scripts prove what the code actually does.
SKILL.md defines how to review.
Report schema makes the result auditable.
```

The project `AGENTS.md` has not been changed yet. Add mandatory design review
instructions there only after the first review results are stable enough for
daily development.
