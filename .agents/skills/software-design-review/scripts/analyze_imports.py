#!/usr/bin/env python3
"""Analyze Python imports against architecture/modules.yaml."""

from __future__ import annotations

import argparse
import ast
import json
from collections import defaultdict
from fnmatch import fnmatch
from pathlib import Path


PRIVATE_MARKERS = (".internal", ".private", "._")
ORM_MARKERS = (".models", ".model", ".repository", ".repositories")


def load_yaml(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        import yaml  # type: ignore
    except Exception as exc:
        return {"_warning": f"PyYAML is unavailable: {exc}"}
    return yaml.safe_load(path.read_text(encoding="utf-8")) or {}


def iter_python_files(root: Path) -> list[Path]:
    ignored = {".git", ".venv", "venv", "node_modules", "__pycache__"}
    files: list[Path] = []
    for path in root.rglob("*.py"):
        if any(part in ignored for part in path.parts):
            continue
        files.append(path)
    return files


def imports_from_file(path: Path) -> list[str]:
    try:
        tree = ast.parse(path.read_text(encoding="utf-8", errors="replace"))
    except SyntaxError:
        return []

    imports: list[str] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imports.extend(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imports.append(node.module)
    return sorted(set(imports))


def module_for_file(file_path: str, modules: dict) -> str | None:
    normalized = file_path.replace("\\", "/")
    for name, config in modules.items():
        for pattern in config.get("paths", []):
            if fnmatch(normalized, pattern):
                return name
    return None


def module_for_import(import_name: str, modules: dict) -> str | None:
    import_path = import_name.replace(".", "/")
    candidates = [f"{import_path}.py", f"{import_path}/__init__.py", f"{import_path}/**"]
    for name, config in modules.items():
        for pattern in config.get("paths", []):
            normalized = pattern.replace("\\", "/")
            if any(fnmatch(candidate, normalized) for candidate in candidates):
                return name
    return None


def visibility(import_name: str, target_module: str | None, modules: dict) -> str:
    if any(marker in f".{import_name}" for marker in PRIVATE_MARKERS):
        return "private"
    if not target_module:
        return "external"
    public_patterns = modules.get(target_module, {}).get("public_paths", [])
    import_path = import_name.replace(".", "/")
    candidates = [f"{import_path}.py", f"{import_path}/__init__.py", f"{import_path}/**"]
    if any(fnmatch(candidate, pattern.replace("\\", "/")) for pattern in public_patterns for candidate in candidates):
        return "public"
    return "internal"


def target_kind(import_name: str) -> str:
    lowered = f".{import_name.lower()}"
    if any(marker in lowered for marker in ORM_MARKERS):
        return "orm_model"
    return "module"


def find_cycles(edges: set[tuple[str, str]]) -> list[list[str]]:
    graph: dict[str, set[str]] = defaultdict(set)
    for source, target in edges:
        graph[source].add(target)

    cycles: list[list[str]] = []
    visiting: list[str] = []
    visited: set[str] = set()

    def visit(node: str) -> None:
        if node in visiting:
            cycle = visiting[visiting.index(node) :] + [node]
            if cycle not in cycles:
                cycles.append(cycle)
            return
        if node in visited:
            return
        visiting.append(node)
        for child in graph.get(node, set()):
            visit(child)
        visiting.pop()
        visited.add(node)

    for node in sorted(graph):
        visit(node)
    return cycles


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=".", help="Repository root")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    config = load_yaml(repo / "architecture" / "modules.yaml")
    modules = config.get("modules", {}) if isinstance(config, dict) else {}
    warnings = []
    if not modules:
        warnings.append("architecture/modules.yaml is missing or has no modules")
    if "_warning" in config:
        warnings.append(config["_warning"])

    cross_module_edges = []
    private_penetrations = []
    orm_dependencies = []
    edge_pairs: set[tuple[str, str]] = set()

    for path in iter_python_files(repo):
        relative = path.relative_to(repo).as_posix()
        source_module = module_for_file(relative, modules)
        if not source_module:
            continue
        for import_name in imports_from_file(path):
            target_module = module_for_import(import_name, modules)
            if not target_module or target_module == source_module:
                continue
            edge_pairs.add((source_module, target_module))
            target_visibility = visibility(import_name, target_module, modules)
            record = {
                "source": source_module,
                "target": target_module,
                "file": relative,
                "import": import_name,
                "target_visibility": target_visibility,
                "target_kind": target_kind(import_name),
            }
            cross_module_edges.append(record)
            if target_visibility in {"internal", "private"}:
                private_penetrations.append(record)
            if record["target_kind"] == "orm_model":
                orm_dependencies.append(record)

    print(
        json.dumps(
            {
                "cross_module_edges": cross_module_edges,
                "private_penetrations": private_penetrations,
                "orm_dependencies": orm_dependencies,
                "cycles": find_cycles(edge_pairs),
                "warnings": warnings,
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
