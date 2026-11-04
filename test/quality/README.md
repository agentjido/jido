# Quality source manifest

`source_manifest.yml` is the source ledger for imported quality assets. Each record identifies the source repository,
full source commit, source path, planned or current target path, quality surface, Covenant owner, disposition, and reason.

Allowed dispositions are:

- `ported`: The target path exists and contains the adapted check.
- `superseded`: A current check owns the same quality obligation.
- `deferred`: A later ticket or product change is required.
- `excluded`: The source asset is outside the supported quality surface.

Target paths must be unique. A `ported` record must point to an existing file or directory. Source paths are records only.
Never edit a source repository while updating this manifest.

## Objective quality contract

`quality_contract.yml` is the normative package-quality definition. It registers each required or opt-in suite, its
owner, fixed seed, code-coverage state, and evidence artifacts. It also owns the package and component coverage floors,
Covenant obligation coverage, fuzz evidence rules, report paths, versioned waivers, and stability findings.

Run the contract check before evidence collection:

```text
mix quality.contract
```

The check rejects missing or duplicate required suites, unknown aliases or states, thresholds below the package rules,
expired or incomplete waivers, unowned stability findings, and evidence paths outside the repository. A required-suite
failure remains in `stability_findings` until its cause is resolved or a versioned waiver records its owner, reason,
expiry date, and resolution condition.

## Component proof map

`component_proof.yml` maps all active Covenant components to one proof profile. Each profile declares unit, Covenant,
authoring, example, property, and fuzz evidence as required or not applicable. A not-applicable result needs a named
owner, a controlled reason code, and a specific reason.

Module ownership starts with the `modules` frontmatter in active Covenant records. Three documented overlaps have an
explicit primary owner. Fallback namespace rules cover modules that do not occur in Covenant frontmatter. The most
specific fallback prefix wins. The committed production and documented-public module counts and SHA-256 values make
new modules fail closed until their ownership is reviewed.

## Coverage measurement

`coverage_baseline.json` records the clean component baseline from its full Git revision. `mix quality.coverage` runs
every required offline suite with ExCoveralls, unions source path and line identities, and writes only ignored evidence
under `tmp/quality/coverage/`. Package lines count once. A module can contribute to each Covenant component that names
it, but it still has one primary owner in `component_proof.yml`.

The gate requires at least 90 percent package coverage and 80 percent for each component. It also fails when a component
drops below its recorded floor or regresses by more than 0.5 percentage points from the committed baseline. The JSON
and text outputs include total and unique covered-line contributions for each suite.

Run the complete coverage gate with:

```text
mix quality.coverage
```

## Focused commands

Each command uses seed `0`. A command exits successfully with a clear message when its default target path does not exist.

```text
mix test.authoring
mix test.contracts
mix test.examples
mix test.property
mix test.fuzz
mix test.system
mix test.load
mix test.peer
mix test.bench
mix test.live
mix test.services
mix test.ci
mix test.all
```

`mix test.ci` runs the default suite and every offline quality surface that is available. Live and service checks stay
explicit and opt-in. `mix test.all` is an equivalent full offline test alias for local use.

`.github/workflows/ci.yml` gives every required offline surface a named job. It
runs Covenant and Reach as required jobs. The objective quality job runs
coverage before the combined report and uploads `tmp/quality/` as a workflow
artifact. Scheduled or manually selected jobs run extended fuzz, load burn-in,
and benchmark checks. Service and live provider jobs require explicit manual
inputs; the live job also requires the dedicated repository test secret.

The static `mix quality` gate blocks highest-priority Credo findings and keeps
the full strict Credo scan visible as advisory debt. Compile warnings,
formatting, Dialyzer, ExDNA, and Reach remain blocking checks.
The checked-in `.dialyzer_ignore.exs` file records existing warnings by file,
warning type, and line. The gate rejects both new warnings and unused baseline
entries.
ExDNA reports all clone groups and rejects an increase above the current
17-clone brownfield baseline.

## Combined quality report

Run `mix quality.coverage` first, then run `mix quality.report`. The report command validates the contract before it
runs the required offline suites. It collects suite artifacts, Covenant obligation coverage, component proof, line
coverage, stability findings, and waivers.

The command writes `tmp/quality/quality.json` and `tmp/quality/quality.txt`. Both files contain the same pass or fail
outcome, the exact Git revision, the dirty state, runtime versions, suite owners, thresholds, coverage, findings, and
waivers. Missing or stale evidence fails closed. A later passing suite does not remove an unresolved stability finding.
