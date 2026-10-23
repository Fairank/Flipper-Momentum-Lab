#!/usr/bin/env python3
"""Compare literal App IDs without executing either tree's Python manifests.

Missing IDs are review candidates, not missing-feature counts. Renamed apps,
plugins, conditional/dynamic declarations and submodules need separate review.
"""
import argparse
import ast
import hashlib
import json
from pathlib import Path


def inventory(root):
    apps, unresolved, errors = [], [], []
    for path in sorted(root.rglob("application.fam")):
        relative = path.relative_to(root).as_posix()
        try:
            data = path.read_bytes()
            tree = ast.parse(data.decode("utf-8"), filename=relative)
        except (OSError, UnicodeError, SyntaxError) as error:
            errors.append({"path": relative, "error": str(error)})
            continue
        for node in ast.walk(tree):
            if (
                not isinstance(node, ast.Call)
                or not isinstance(node.func, ast.Name)
                or node.func.id != "App"
            ):
                continue
            fields = {kw.arg: kw.value for kw in node.keywords}
            entry = {
                "path": relative,
                "line": node.lineno,
                "manifest_sha256": hashlib.sha256(data).hexdigest(),
            }
            for name in ("appid", "name", "fap_version", "fap_category"):
                value = fields.get(name)
                if isinstance(value, ast.Constant):
                    entry[name] = value.value
            apptype = fields.get("apptype")
            if isinstance(apptype, ast.Attribute):
                entry["apptype"] = apptype.attr
            if isinstance(entry.get("appid"), str):
                apps.append(entry)
            else:
                entry["reason"] = (
                    "App ID is not a literal; do not evaluate untrusted manifest code"
                )
                unresolved.append(entry)
    return {"apps": apps, "unresolved": unresolved, "errors": errors}


def compare(current_roots, reference_root, reference_commit):
    current = {"apps": [], "unresolved": [], "errors": []}
    for root in current_roots:
        part = inventory(root)
        for kind in current:
            for entry in part[kind]:
                current[kind].append(dict(entry, path=root.name + "/" + entry["path"]))
    reference = inventory(reference_root)
    ids = {app["appid"] for app in current["apps"]}
    reference_ids = {app["appid"] for app in reference["apps"]}
    missing = [app for app in reference["apps"] if app["appid"] not in ids]
    return {
        "format_version": 1,
        "reference_commit": reference_commit,
        "scope_note": __doc__,
        "counts": {
            "current_literal_ids": len(ids),
            "reference_literal_ids": len(reference_ids),
            "shared_literal_ids": len(ids & reference_ids),
            "reference_ids_absent_from_current": len(reference_ids - ids),
        },
        "reference_candidates_absent_from_current": missing,
        "current": current,
        "reference": reference,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root", type=Path, default=Path(__file__).resolve().parents[1]
    )
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--reference-commit", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    roots = [
        args.root / "applications" / name
        for name in ("main", "services", "settings", "system", "external", "union")
    ]
    roots.append(args.root / "applications_user")
    if not (args.reference.is_dir() and any(args.reference.rglob("application.fam"))):
        parser.error("reference must contain the checked out application manifests")
    report = compare(roots, args.reference, args.reference_commit)
    args.output.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(report["counts"]))
    return int(bool(report["current"]["errors"] or report["reference"]["errors"]))


if __name__ == "__main__":
    raise SystemExit(main())
