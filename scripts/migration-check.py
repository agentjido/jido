#!/usr/bin/env python3
"""Run one local migration check and save its command, revision, and results."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

root = Path(__file__).resolve().parents[1]
name, *command = sys.argv[1:]
assert name and all(c.isalnum() or c in "-_" for c in name), "Invalid evidence name"
if command and command[0] == "--":
    command.pop(0)
evidence = root / "docs/migration/evidence/core"
evidence.mkdir(parents=True, exist_ok=True)
result_path = evidence / f"{name}.results.jsonl"
result_path.unlink(missing_ok=True)
env = os.environ.copy()
if command[:2] == ["mix", "test"]:
    command += ["--formatter", "ExUnit.CLIFormatter", "--formatter", "JidoTest.MigrationFormatter"]
    env["JIDO_MIGRATION_RESULTS"] = str(result_path)

def output(*args):
    return subprocess.check_output(args, cwd=root, text=True).strip()


code_paths = output("git", "ls-files", "--cached", "--others", "--exclude-standard").splitlines()
code_hashes = {
    name: hashlib.sha256((root / name).read_bytes()).hexdigest()
    for name in sorted(set(code_paths))
    if (root / name).is_file()
    and (name.startswith(("lib/", "test/", "config/", "scripts/"))
         or name in {"mix.exs", "mix.lock", ".formatter.exs", ".credo.exs"})
}

record = {
    "command": command,
    "revision": output("git", "rev-parse", "HEAD"),
    "tracked_tree": output("git", "write-tree"),
    "code_sha256": hashlib.sha256(json.dumps(code_hashes, sort_keys=True).encode()).hexdigest(),
    "code_files": code_hashes,
    "branch": output("git", "branch", "--show-current"),
    "status_before": output("git", "status", "--porcelain"),
    "runtime": output("elixir", "--version"),
    "cwd": str(root),
    "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "log": f"{name}.log",
}
started = time.monotonic()
with (evidence / record["log"]).open("w") as log:
    run = subprocess.run(command, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT)
record["exit_code"] = run.returncode
record["duration_seconds"] = round(time.monotonic() - started, 3)
if result_path.exists():
    suites = [json.loads(line) for line in result_path.read_text().splitlines()]
    record["suites"] = []
    for suite in suites:
        counts = {}
        for test in suite["tests"]:
            counts[test["status"]] = counts.get(test["status"], 0) + 1
        record["suites"].append(counts)
    record["results"] = result_path.name
(evidence / f"{name}.json").write_text(json.dumps(record, indent=2) + "\n")
print(json.dumps({key: value for key, value in record.items()
                  if key not in {"code_files", "status_before"}}, indent=2))
sys.exit(run.returncode)
