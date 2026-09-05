#!/usr/bin/env python3
"""Measure one fixed candidate in fresh VMs. Does not edit or push code."""
import argparse
import json
import os
from pathlib import Path
import signal
import statistics
import subprocess
import sys


def positive(value):
    number = int(value)
    if not 1 <= number <= 50:
        raise argparse.ArgumentTypeError("rounds must be between 1 and 50")
    return number


def run(command, cwd, env, log, timeout):
    with log.open("w") as output:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=output,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
            if code:
                raise RuntimeError(f"command failed ({code}); see {log}")
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()


def compatible(before, after):
    for key in ("schema_version", "environment", "settings", "method"):
        if before[key] != after[key]:
            raise ValueError(f"different {key}")
    if before["source"]["tool_sha256"] != after["source"]["tool_sha256"]:
        raise ValueError("different benchmark tools")
    for report in (before, after):
        ids = [row["id"] for row in report["cases"]]
        if not ids or len(ids) != len(set(ids)):
            raise ValueError("empty or duplicate case IDs")
        if any(row["resources"]["median"]["owned_remaining"] != 0
               for row in report["cases"]):
            raise ValueError("owned processes remain")
    if {row["id"] for row in before["cases"]} != {row["id"] for row in after["cases"]}:
        raise ValueError("different case sets")


def identity(report):
    source = report["source"]
    if source["runtime_dirty"]:
        raise ValueError("commit runtime changes before paired measurements")
    return {key: source[key] for key in ("commit", "runtime_sha256", "tool_sha256")}


def ratio(after, before):
    return after / before if before else None


def measurements(row):
    resource = row["resources"]["median"]
    values = {
        "time": row["timing"]["wall_ns"]["median"],
        "p95": row["timing"]["wall_ns"]["p95"],
        "caller_reductions": row["timing"]["caller_reductions"]["median"],
        "process_bytes": resource["observed_peak"]["process_memory_bytes"],
        "binary_bytes": resource["observed_peak"]["shared_binary_bytes"],
    }
    values.update({f"copied_heap/{name}": term["copied_flat_heap_bytes"]
                   for name, term in row["retained_terms"].items()})
    return values


def display(value):
    return "unavailable" if value is None else f"{value:.3f}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--profile", choices=("smoke", "short", "scale"), default="short")
    parser.add_argument("--filter")
    parser.add_argument("--rounds", type=positive, default=5)
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    if args.timeout < 1:
        parser.error("timeout must be positive")
    roots = {"baseline": args.baseline.resolve(), "candidate": args.candidate.resolve()}
    for root in roots.values():
        if not (root / "mix.exs").is_file():
            parser.error(f"not a Mix project: {root}")
    output = args.output.resolve()
    if output.exists() and any(output.iterdir()):
        parser.error("output directory must be empty")
    output.mkdir(parents=True, exist_ok=True)
    scripts = Path(__file__).resolve().parent
    env = os.environ.copy()
    env["ERL_FLAGS"] = "+S 2:2"
    env["MIX_ENV"] = "dev"
    # Separate project defaults must own the builds and dependency directories.
    for key in ("MIX_BUILD_PATH", "MIX_DEPS_PATH", "MIX_BUILD_ROOT"):
        env.pop(key, None)
    pairs, identities, ratios = [], {}, {}
    manifest = {"status": "running", "profile": args.profile, "rounds": args.rounds,
                "roots": {key: str(value) for key, value in roots.items()}, "pairs": pairs}
    manifest_path = output / "manifest.json"
    try:
        for side, root in roots.items():
            print(f"Compile {side} before measurement", flush=True)
            run(["mix", "compile", "--warnings-as-errors"], root, env,
                output / f"{side}-compile.log", args.timeout)
        for number in range(1, args.rounds + 1):
            directory = output / f"pair-{number:02d}"
            directory.mkdir()
            order = ["baseline", "candidate"] if number % 2 else ["candidate", "baseline"]
            reports = {}
            for side in order:
                print(f"Pair {number}/{args.rounds}: {side}", flush=True)
                destination = directory / side
                command = ["mix", "run", "--no-compile", str(scripts / "run.exs"),
                           "--profile", args.profile, "--output", str(destination)]
                if args.filter:
                    command.extend(["--filter", args.filter])
                run(command, roots[side], env, directory / f"{side}.log", args.timeout)
                report = json.loads((destination / "report.json").read_text())
                current = identity(report)
                if side in identities and current != identities[side]:
                    raise ValueError(f"{side} source or tool changed during the run")
                identities[side] = current
                reports[side] = report
            compatible(reports["baseline"], reports["candidate"])
            if pairs:
                compatible(first_report, reports["baseline"])
            else:
                first_report = reports["baseline"]
            old = {row["id"]: row for row in reports["baseline"]["cases"]}
            for row in reports["candidate"]["cases"]:
                before, after = measurements(old[row["id"]]), measurements(row)
                if before.keys() != after.keys():
                    raise ValueError("retained term names changed")
                metrics = ratios.setdefault(row["id"], {})
                for key, value in after.items():
                    metrics.setdefault(key, []).append(ratio(value, before[key]))
            pairs.append({"number": number, "order": order,
                          "directory": str(directory), "sources": dict(identities)})
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
        summary = {}
        for case, metrics in ratios.items():
            summary[case] = {}
            for metric, values in metrics.items():
                available = [value for value in values if value is not None]
                summary[case][metric] = {
                    "ratios": values,
                    "median": statistics.median(available) if available else None,
                    "improved_pairs": sum(value < 1 for value in available),
                }
        (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        lines = ["# Paired Jido core measurements", "",
                 "Ratios are candidate / baseline. This report does not accept a code change.", "",
                 "| Case | Median time ratio | Lower-time pairs | Process byte ratio |",
                 "| --- | ---: | ---: | ---: |"]
        for case, values in sorted(summary.items()):
            lines.append(f"| {case} | {display(values['time']['median'])} | "
                         f"{values['time']['improved_pairs']}/{args.rounds} | "
                         f"{display(values['process_bytes']['median'])} |")
        (output / "summary.md").write_text("\n".join(lines) + "\n")
        manifest["status"] = "complete"
    except BaseException as error:
        manifest["status"] = "failed"
        manifest["error"] = str(error)
        raise
    finally:
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"Benchmark failed: {error}", file=sys.stderr)
        sys.exit(1)
