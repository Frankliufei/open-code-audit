#!/usr/bin/env python3
"""Collect extension-cost signals from changed Python files."""

from __future__ import annotations

import argparse
import ast
import json
import re
import subprocess
from collections import Counter
from pathlib import Path


TYPE_SWITCH_RE = re.compile(
    r"\b(if|elif)\s+[\w.]*?(type|kind|key|provider|adapter|backend)[\w.]*\s*=="
)
MATCH_RE = re.compile(r"\bmatch\s+[\w.]*?(type|kind|key|provider|adapter|backend)\b")
REGISTRY_RE = re.compile(r"\b(register|registry|providers|adapters)\b", re.IGNORECASE)


def git_changed_files(repo: Path, base: str) -> tuple[list[str], list[str]]:
    check = subprocess.run(
        ["git", "rev-parse", "--is-inside-work-tree"],
        cwd=repo,
        text=True,
        capture_output=True,
        check=False,
    )
    if check.returncode != 0:
        return [], ["not a git repository"]

    proc = subprocess.run(
        ["git", "diff", "--name-only", base],
        cwd=repo,
        text=True,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        return [], [proc.stderr.strip() or "git diff failed"]
    return [line for line in proc.stdout.splitlines() if line.endswith(".py")], []


def all_python_files(repo: Path) -> list[str]:
    ignored = {".git", ".venv", "venv", "node_modules", "__pycache__"}
    return [
        path.relative_to(repo).as_posix()
        for path in repo.rglob("*.py")
        if not any(part in ignored for part in path.parts)
    ]


def class_and_function_changes(source: str) -> dict[str, int]:
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return {"classes": 0, "functions": 0}
    return {
        "classes": sum(isinstance(node, ast.ClassDef) for node in ast.walk(tree)),
        "functions": sum(
            isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
            for node in ast.walk(tree)
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=".", help="Repository root")
    parser.add_argument("--base", default="HEAD", help="Base revision")
    parser.add_argument(
        "--all",
        action="store_true",
        help="Scan all Python files instead of only changed files",
    )
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    warnings: list[str] = []
    files = all_python_files(repo) if args.all else []
    if not files:
        files, warnings = git_changed_files(repo, args.base)
    if not files and warnings:
        files = all_python_files(repo)
        warnings.append("falling back to all Python files")

    type_dispatch_branches = []
    match_dispatches = []
    registry_touches = []
    repeated_literals: Counter[str] = Counter()
    symbol_counts = {}

    for file_path in files:
        path = repo / file_path
        if not path.exists():
            continue
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        symbol_counts[file_path] = class_and_function_changes("\n".join(lines))
        for lineno, line in enumerate(lines, start=1):
            if TYPE_SWITCH_RE.search(line):
                type_dispatch_branches.append({"file": file_path, "line": lineno, "text": line.strip()})
            if MATCH_RE.search(line):
                match_dispatches.append({"file": file_path, "line": lineno, "text": line.strip()})
            if REGISTRY_RE.search(line):
                registry_touches.append({"file": file_path, "line": lineno, "text": line.strip()})
            for literal in re.findall(r"['\"]([A-Za-z][A-Za-z0-9_-]{2,})['\"]", line):
                repeated_literals[literal] += 1

    print(
        json.dumps(
            {
                "scanned_files": files,
                "type_dispatch_branches": type_dispatch_branches,
                "match_dispatches": match_dispatches,
                "registry_touches": registry_touches,
                "repeated_literals": [
                    {"literal": value, "count": count}
                    for value, count in repeated_literals.most_common()
                    if count >= 3
                ],
                "symbol_counts": symbol_counts,
                "warnings": warnings,
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
