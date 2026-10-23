#!/usr/bin/env python3
"""Resolve app-ID gaps against entry points, labels and actual source contents.

Identical app-local source is evidence of an alias, not proof of runtime parity:
firmware APIs, linked libraries, resources and hardware still need verification.
Manifests are parsed as AST data, never executed.
"""
import argparse
import ast
from collections import Counter
import hashlib
import json
from pathlib import Path

from audit_app_union import compare

CODE = {".c", ".h", ".cpp", ".hpp", ".cc", ".s", ".S", ".js"}


def entry_point(root, entry):
    tree = ast.parse((root / entry["path"]).read_text(encoding="utf-8"))
    for node in ast.walk(tree):
        if (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id == "App"
        ):
            fields = {item.arg: item.value for item in node.keywords}
            appid = fields.get("appid")
            if isinstance(appid, ast.Constant) and appid.value == entry["appid"]:
                value = fields.get("entry_point")
                return value.value if isinstance(value, ast.Constant) else None
    return None


def signature(directory):
    # Ignore filename changes when identifying app-ID renames; keep a multiset
    # so duplicated or removed compilation units cannot disappear in a set.
    hashes = sorted(
        hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
        for path in directory.rglob("*")
        if path.suffix in CODE and path.is_file()
    )
    return hashlib.sha256("\n".join(hashes).encode()).hexdigest() if hashes else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root", type=Path, default=Path(__file__).resolve().parents[1]
    )
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--reference-commit", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    if (
        not root.is_dir()
        or not args.reference.is_dir()
        or not any(args.reference.rglob("application.fam"))
    ):
        parser.error(
            "Both source trees must exist and the reference must contain application manifests"
        )
    roots = [
        root / "applications" / name
        for name in ("main", "services", "settings", "system", "external", "union")
    ]
    roots.append(root / "applications_user")
    report = compare(roots, args.reference, args.reference_commit)
    # audit_app_union prefixes root.name. Resolve each prefix unambiguously.
    base = {path.name: path.parent for path in roots}
    cache = {}
    for entry in report["current"]["apps"]:
        path = Path(entry["path"])
        entry["path"] = (base[path.parts[0]] / path).relative_to(root).as_posix()
    current = report["current"]["apps"]
    reference = report["reference"]["apps"]
    for entries, directory in ((current, root), (reference, args.reference)):
        for entry in entries:
            entry["entry_point"] = entry_point(directory, entry)
            folder = directory / Path(entry["path"]).parent
            if folder not in cache:
                cache[folder] = signature(folder)
            entry["source_signature"] = cache[folder]
    findings = []
    for other in reference:
        matches = [entry for entry in current if entry["appid"] == other["appid"]]
        reason = "same_id"
        if not matches:
            matches = [
                entry
                for entry in current
                if other["entry_point"] and entry["entry_point"] == other["entry_point"]
            ]
            reason = "same_entry_point"
        if not matches:
            matches = [
                entry
                for entry in current
                if other.get("name") and entry.get("name") == other["name"]
            ]
            reason = "same_display_name"
        if not matches:
            matches = [
                entry
                for entry in current
                if other["source_signature"]
                and entry["source_signature"] == other["source_signature"]
            ]
            reason = "same_app_local_source"
        if matches:
            identical = any(
                entry["source_signature"]
                and entry["source_signature"] == other["source_signature"]
                for entry in matches
            )
            if other["source_signature"] is None or all(
                entry["source_signature"] is None for entry in matches
            ):
                status = "matched_source_unavailable_review_required"
            else:
                status = (
                    "app_local_source_identical"
                    if identical
                    else "matched_source_differs_review_required"
                )
        else:
            status = (
                "unmatched_plugin"
                if other.get("apptype") == "PLUGIN"
                else "unmatched_application"
            )
            reason = "none"
        findings.append(
            {
                "reference": other,
                "status": status,
                "matched_by": reason,
                "candidates": matches,
            }
        )
    output = {
        "format_version": 1,
        "reference_commit": args.reference_commit,
        "scope": __doc__,
        "counts": dict(Counter(row["status"] for row in findings)),
        "findings": findings,
        "parse_errors": report["current"]["errors"] + report["reference"]["errors"],
        "unresolved_manifests": report["current"]["unresolved"]
        + report["reference"]["unresolved"],
    }
    args.output.write_text(
        json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(output["counts"]))
    return int(bool(output["parse_errors"]))


if __name__ == "__main__":
    raise SystemExit(main())
