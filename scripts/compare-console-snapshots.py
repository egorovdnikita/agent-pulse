#!/usr/bin/env python3
"""Сравнить все PNG двух нативных экспортов Пульта, включая альфа-канал."""
import argparse
import json
from pathlib import Path

from PIL import Image


def compare(baseline: Path, candidate: Path, allow_new: bool) -> dict:
    expected = {path.name: path for path in baseline.glob("*.png")}
    actual = {path.name: path for path in candidate.glob("*.png")}
    if not expected:
        raise ValueError("В исходной папке нет PNG")
    missing = sorted(expected.keys() - actual.keys())
    added = sorted(actual.keys() - expected.keys())
    changed = []
    for name in sorted(expected.keys() & actual.keys()):
        with Image.open(expected[name]) as first, Image.open(actual[name]) as second:
            first, second = first.convert("RGBA"), second.convert("RGBA")
            if first.size != second.size or first.tobytes() != second.tobytes():
                changed.append(name)
    return {
        "checked": len(expected.keys() & actual.keys()),
        "changed": changed,
        "missing": missing,
        "added": added,
        "passed": not changed and not missing and (allow_new or not added),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--allow-new", action="store_true")
    args = parser.parse_args()
    try:
        result = compare(args.baseline, args.candidate, args.allow_new)
    except (ValueError, OSError) as error:
        parser.exit(2, str(error) + "\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
