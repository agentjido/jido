"""Check the evolving core target against the recorded transfer ledger."""

import hashlib
import json
from pathlib import Path
import sys

plan = Path(__file__).resolve().parent
root = plan.parent.parent
source = json.loads((plan / "sources.json").read_text())
transfer = json.loads((plan / "transfer-plan.json").read_text())
hashes = {row["path"]: row["sha256"] for row in source["donor_files"]}
stage = sys.argv[1] if len(sys.argv) > 1 else "M01"
assert stage in [f"M{i:02}" for i in range(1, 15)], stage
targets = [row["target"] for row in transfer["files"]]
assert len(targets) == len(set(targets)), "Target collision"
checked = 0
for row in transfer["files"]:
    assert row["source"] in hashes, row
    if row["stage"] > stage:
        continue
    target = root / row["target"]
    assert target.is_file(), f"Missing target: {target}"
    actual = hashlib.sha256(target.read_bytes()).hexdigest()
    expected = row.get("core_sha256", hashes[row["source"]])
    if "core_sha256" in row:
        assert row.get("reason") and row.get("checks"), row
    assert actual == expected, f"Unrecorded source change: {target}"
    checked += 1
print(json.dumps({"stage": stage, "checked_targets": checked, "status": "pass"}))
