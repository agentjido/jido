#!/usr/bin/env python3
"""Check every source test introduced through the current migration stage."""

import collections
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
plan = root / "docs/migration"
stage, result_name = sys.argv[1:]
subprocess.run([sys.executable, str(plan / "verify_target.py"), stage], check=True)
manifest = json.loads((plan / "example-manifest.json").read_text())
baseline = json.loads((plan / "evidence/prepared/scoped-final-full-seed-0.results.jsonl").read_text())
runs = [json.loads(line) for line in Path(result_name).read_text().splitlines()]
assert len(runs) == 1, "Expected one full suite"
tests = runs[0]["tests"]
assert tests, "Empty suite"
identity = lambda row: (row["file"], row["name"])
actual = {identity(row): row for row in tests}
assert len(actual) == len(tests), "Duplicate test identity"
expected = {identity(row) for row in baseline["tests"] if (root / row["file"]).is_file()}
assert expected <= actual.keys(), f"Missing source tests: {sorted(expected - actual.keys())}"
allowed = {identity(row) for row in manifest["allowed_skips"]}
for row in tests:
    assert row["status"] == "passed" or (
        row["status"] in {"excluded", "skipped"} and identity(row) in allowed
    ), row
report = []
for category in ["catalog", "shared_group_files", "integration_scenarios", "research"]:
    for row in manifest[category]:
        paths = row.get("target_tests", row.get("prepared_tests", []))
        if not paths or not all((root / p).is_file() for p in paths):
            continue
        selected = [test for test in tests if test["file"] in paths]
        for path in paths:
            assert any(t["file"] == path for t in selected), f"Empty selection: {path}"
        assert len(selected) >= row.get("source_tests_selected", row["baseline_tests_executed"])
        report.append({"category": category, "id": row.get("core_id", row.get("id", row.get("group"))),
                       "counts": dict(collections.Counter(t["status"] for t in selected)),
                       "tests": selected})
output = Path(result_name).with_suffix(".stage.json")
output.write_text(json.dumps({"stage": stage, "source_tests_retained": len(expected),
    "suite_counts": dict(collections.Counter(t["status"] for t in tests)),
    "contracts": report}, indent=2) + "\n")
print(json.dumps({"stage": stage, "source_tests_retained": len(expected),
    "contracts": len(report), "status": "pass"}))
