#!/usr/bin/env python3
"""Collect changed files and import deltas for design review."""

from __future__ import annotations

import argparse
import ast
import json
import subprocess
from pathlib import Path


def run_git(args: list[str], cwd: Path) -> tuple[int, str, str]:
    proc = subprocess.run(
        ["git", *args],
        cwd=cwd,
        text=True,
        capture_output=True,
        check=False,
    )
    return proc.returncode, proc.stdout, proc.stderr


def is_git_repo(cwd: Path) -> bool:
    code, _, _ = run_git(["rev-parse", "--is-inside-work-tree"], cwd)
    return code == 0


def imports_from_source(source: str) -> list[str]:
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return []

    imports: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imports.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            if node.module:
                imports.add(node.module)
    return sorted(imports)


def file_at_revision(repo: Path, revision: str, file_path: str) -> str:
    code, stdout, _ = run_git(["show", f"{revision}:{file_path}"], repo)
    return stdout if code == 0 else ""


def current_file(repo: Path, file_path: str) -> str:
    path = repo / file_path
    if not path.exists() or not path.is_file():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def infer_module(file_path: str, modules: dict[str, object]) -> str | None:
    from fnmatch import fnmatch

    normalized = file_path.replace("\\", "/")
    for module_name, config in modules.items():
        paths = config.get("paths", []) if isinstance(config, dict) else []
        if any(fnmatch(normalized, pattern) for pattern in paths):
            return module_name
    return None


def load_modules(repo: Path) -> dict[str, object]:
    modules_file = repo / "architecture" / "modules.yaml"
    if not modules_file.exists():
        return {}
    try:
        import yaml  # type: ignore
    except Exception:
        return {}
    data = yaml.safe_load(modules_file.read_text(encoding="utf-8")) or {}
    return data.get("modules", {}) if isinstance(data, dict) else {}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=".", help="Repository root")
    parser.add_argument("--base", default="HEAD", help="Base revision")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    if not is_git_repo(repo):
        print(
            json.dumps(
                {
                    "base_revision": args.base,
                    "changed_files": [],
                    "changed_modules": [],
                    "added_imports": [],
                    "removed_imports": [],
                    "warnings": ["not a git repository"],
                },
                indent=2,
            )
        )
        return 0

    code, stdout, stderr = run_git(["diff", "--name-only", args.base], repo)
    if code != 0:
        print(
            json.dumps(
                {
                    "base_revision": args.base,
                    "changed_files": [],
                    "changed_modules": [],
                    "added_imports": [],
                    "removed_imports": [],
                    "warnings": [stderr.strip() or "git diff failed"],
                },
                indent=2,
            )
        )
        return 0

    changed_files = [line.strip() for line in stdout.splitlines() if line.strip()]
    modules = load_modules(repo)
    changed_modules = sorted(
        {
            module
            for file_path in changed_files
            for module in [infer_module(file_path, modules)]
            if module
        }
    )

    added_imports: list[dict[str, str]] = []
    removed_imports: list[dict[str, str]] = []
    for file_path in changed_files:
        if not file_path.endswith(".py"):
            continue
        before = set(imports_from_source(file_at_revision(repo, args.base, file_path)))
        after = set(imports_from_source(current_file(repo, file_path)))
        added_imports.extend(
            {"file": file_path, "import": value} for value in sorted(after - before)
        )
        removed_imports.extend(
            {"file": file_path, "import": value} for value in sorted(before - after)
        )

    print(
        json.dumps(
            {
                "base_revision": args.base,
                "changed_files": changed_files,
                "changed_modules": changed_modules,
                "added_imports": added_imports,
                "removed_imports": removed_imports,
                "tests_changed": [
                    file_path
                    for file_path in changed_files
                    if "test" in Path(file_path).name.lower()
                    or "/tests/" in file_path.replace("\\", "/")
                ],
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
