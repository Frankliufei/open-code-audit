# Tool Requirements

The skill packages orchestration, rules, and reporting. It does not vendor
external tools or local tool source trees.

## Tool Resolution Order

Scripts should resolve tools in this order:

1. Environment variable override.
2. Project-local `node_modules/.bin`.
3. Global `PATH`.
4. Known local fallback paths for the current workstation.

## Environment Variables

- `OCR_BIN`: path to `ocr` or `ocr.exe`.
- `CODEBASE_MEMORY_BIN`: path to `codebase-memory-mcp`.
- `CODE_QUALITY_AUDIT_SCRIPT`: path to `run_audit.ps1`.
- `RUFF_BIN`: path to `ruff` or `ruff.exe`.
- `SEMGREP_BIN`: path to `semgrep` or `semgrep.exe`.
- `IMPORT_LINTER_BIN`: path to `lint-imports` or `lint-imports.exe`.
- `PYTHON_AUDIT_TOOLS_ROOT`: optional root for the dedicated Python audit
  tools venv. Defaults to
  `%LOCALAPPDATA%\CodexTools\software-design-review-python-audit`.

## External Tools

### open-code-review

Purpose: AI review for bugs, security, performance, and code quality comments.

Expected command:

```powershell
ocr review --audience agent --background "context"
```

Install option:

```powershell
npm install -g @alibaba-group/open-code-review
```

### codebase-memory-mcp

Purpose: code map, architecture overview, symbol search, call graph, dependency
queries.

Expected command:

```powershell
codebase-memory-mcp cli index_repository '{"repo_path":"D:/path/to/repo"}'
```

Prefer the active MCP tools when available inside Codex. The wrapper script only
uses the CLI when it is installed.

### code-quality-audit

Purpose: deterministic local audit using Ruff, Semgrep, Import Linter, and
optionally SonarQube.

Expected command:

```powershell
run_audit.ps1 -Target D:\path\to\repo -OutputRoot D:\path\to\reports
```

The current workstation fallback path is:

```text
D:\work\code-quanlity-analysis\tools\code-quality-audit\scripts\run_audit.ps1
```

### Python audit tools

Purpose: local static checks used by `code-quality-audit`.

Expected commands:

```powershell
ruff --version
semgrep --version
lint-imports --version
```

Install option:

```powershell
.\.agents\skills\software-design-review\scripts\install_tools.ps1
```

These tools are part of the standard integration chain. Use
`install_tools.ps1 -SkipPythonAuditTools` only when a machine intentionally runs
the governance wrapper without full local quality checks.

The installer puts these packages in a dedicated venv instead of the global
Python environment:

```text
%LOCALAPPDATA%\CodexTools\software-design-review-python-audit\.venv
```

This keeps Semgrep's dependency set isolated from other local Python tooling.

## Packaging Rule

Package this skill directory and architecture templates. Do not package:

- external repository clones;
- global npm packages;
- `.venv` directories;
- tool caches;
- large binaries.

This keeps the skill portable across machines.
