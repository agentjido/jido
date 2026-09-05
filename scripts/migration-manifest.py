#!/usr/bin/env python3
"""Check every retained fixture and map a complete ExUnit result to its contract."""
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
folder = root / "docs/migration"
manifest = json.loads((folder / "example-manifest.json").read_text())
assert len(manifest["catalog"]) == 52
assert len(manifest["integration_scenarios"]) == 10
assert len({r["id"] for r in manifest["catalog"]}) == 52
subprocess.run(["git", "merge-base", "--is-ancestor", manifest["core_base_commit"], "HEAD"], cwd=root, check=True)
paths = set(manifest["prepared_support_files"] + manifest["prepared_topology_core_tests"])
contracts = []
for category in ["catalog", "shared_group_files", "integration_scenarios", "research"]:
    for row in manifest[category]:
        paths.update(row["prepared_files"])
        paths.update(row["prepared_tests"])
        if row.get("prepared_profile"):
            paths.add(row["prepared_profile"])
        if row["prepared_tests"]:
            contracts.append((category, row.get("id", row.get("group")), row["prepared_tests"], row["baseline_tests_executed"]))
contracts.append(("supporting_core", "topology", manifest["prepared_topology_core_tests"], 1))
regressions = manifest.get("required_regression_tests", [])
paths.update(regressions)
if regressions:
    contracts.append(("required_regressions", "preparation", regressions, 1))
missing = sorted(p for p in paths if not (root / p).is_file())
assert not missing, f"Missing prepared paths: {missing}"
print(f"Verified {len(paths)} paths, 52 catalog fixtures, and 10 application scenarios.")
if len(sys.argv) == 1:
    sys.exit(0)
results = [json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines()]
assert len(results) == 1, "Use one complete suite result."
tests = results[0]["tests"]
allowed_skips = {
    (row["file"], row["name"])
    for row in manifest.get("allowed_skips", [])
}
report = []
for category, identity, test_paths, minimum in contracts:
    selected = [t for t in tests if t["file"] in test_paths]
    for path in test_paths:
        assert any(t["file"] == path for t in selected), f"Empty test selection: {path}"
    assert len(selected) >= minimum, f"Test count decreased: {identity}"
    counts = {}
    for test in selected:
        counts[test["status"]] = counts.get(test["status"], 0) + 1
    report.append({"category": category, "id": identity, "counts": counts, "tests": selected})
output = Path(sys.argv[1]).with_suffix(".manifest.json")
output.write_text(json.dumps(report, indent=2) + "\n")
def accepted(test):
    return test["status"] == "passed" or (
        test["status"] in {"skipped", "excluded"} and (test["file"], test["name"]) in allowed_skips
    )

failed = [row for row in report if any(not accepted(test) for test in row["tests"])]
unexpected = [test for test in tests if not accepted(test)]
skipped = [{"file": test["file"], "name": test["name"], "status": test["status"]} for test in tests if test["status"] in {"skipped", "excluded"}]
print(json.dumps({"result": str(output), "allowed_skips_observed": skipped,
    "unexpected_results": [{"file": test["file"], "name": test["name"], "status": test["status"]} for test in unexpected],
    "nonpassing_contracts": [{"category": r["category"], "id": r["id"], "counts": r["counts"]} for r in failed]}, indent=2))
sys.exit(bool(failed or unexpected))
