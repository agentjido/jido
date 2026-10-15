# Agent API contract

`jido.agent` protects the public path from declaration to definition, instance,
and direct command. It has 25 active obligations. The obligation IDs refine the
Agent, Turn, effect, Plugin, and error promises in `guides/public-contracts.md`.

Read `jido/agent.obligations.md` for the promises and
`jido/agent.decisions.yml` for the scope decisions. The implementation module
list selects mutation targets. It does not expose internal APIs.

See [the Agent baseline](jido/agent.baseline.md) for the local test and coverage
results, the earlier full mutation run, and the focused checks after review.

## Local dependency

Development and tests use `../covenant`, with `runtime: false`. The pilot uses
Mike Hostetler's `feat/macro-mutation` fork at commit
`72609acff92ed82da69a640100c35159323e2df0`. Keep that checkout beside `jido`.
The fork's default `main` branch does not provide this macro mutation support.
A CI checkout must supply this sibling dependency, as it supplies the other
local path dependencies. This local rollout does not publish the fork.

Run these commands from `jido`:

```sh
mix deps.get
mix test.contract
mix test.ci
```

`mix test.contract` runs Covenant's passing-test gate and writes
`contracts/coverage.json`. All 25 obligations must have passing tests. Core tests,
property tests, and the contract gate run through `mix test.ci`. `mix quality`
also runs the contract gate. Keep the existing package line-coverage gate.

## Mutation review

The macro run covers the 20 files listed in the obligations front matter.
It runs only the public API contract tests. It does not mutate AgentServer,
Topology, or dependency packages. Directives are returned without dispatch.
Fixtures use fresh module namespaces and wait for compiler exit, including
`after_verify`, before assertions or cleanup. No precompiled Agent fixture is
used, so this suite needs no extra `--recompile` arguments.

Workers use private project copies. Each worker retires after 50 mutations and
must pass the original tests before it stops. Use one worker for a first local
check, then increase concurrency. The default matrix is
`tmp/covenant/mutate/jido.agent/kill_matrix.json`. Keep the complete matrix when
reviewing changes to the protected code.

For each survivor, add a test if the change breaks a promise. Otherwise, record
the exact site, operator, change, and a specific reason in
`jido/agent.survivors.yml`. Do not accept `evaluation-gap`, `timeout`, or partial
runs as a complete result. Covenant rejects stale survivor entries. Error text
that the API leaves open can have an `unpromised` entry; preserve promised error
types, subjects, cause fields, and source locations.

Mutation credit and line coverage answer different questions. An invalid mutant
has no kill credit. A fail-fast run has partial obligation credit. Use a complete
run without `--fail-fast` for the obligation matrix.

For a focused check, select IDs from a matrix made with the same source and
module profile. IDs can change when source changes. Check the reported sites.
The three test gaps found in this rollout can be checked with:

```sh
MIX_ENV=test mix covenant.mutate jido.agent --macros \
  --only m0684,m0985,m1034 --jobs 1 --seed 0 --timeout 5000 \
  --max-runtime 120000 --out tmp/covenant/agent-focused.json
```

This runs all 76 contract tests for each selected mutant. It gives exact test
attribution for these three mutants. It does not verify the other 1,299 mutants.
For a shorter development check, add `--fail-fast` and
`--prioritize tmp/covenant/agent-focused.json`, and use a different output path.
Prior results select a test to run first; every verdict is measured again.
Known annotations outside the selection are deferred. Unknown annotations and
stale annotations within the selection still fail.

A complete mutation review is a separate checkpoint check:

```sh
MIX_ENV=test mix covenant.mutate jido.agent --macros --jobs 4 --seed 0 \
  --timeout 5000 --max-runtime 3600000
```

The rollout baseline keeps the earlier full run and the later focused result
separate. The second full run was cancelled. Do not combine their counts into
a new full-run score.

## Limits

The fork skips structural declarations, compiler attributes in some contexts,
and quoted code outside macro definitions. In particular, the ordinary
`Jido.Agent.DSL.Generator.function/3` function returns quoted helper code that
is not mutated inside the quote. Explicit helper tests protect this code.
Generic mutation operators do not produce every semantic defect, such as all
possible argument swaps. Fixed input examples and the existing property tests
remain required.

This contract does not cover checkpoint/restore behavior, AgentServer,
Topology deployment, persistence backends, or Directive dispatch. Source value
immutability cannot undo external work that an Action already performed.
Initialization follows Zoi input defaults, including nil-triggered defaults;
stored and candidate validation does not reapply defaults.

The Spark provider file `lib/jido/agent/dsl/extension.ex` is excluded from the
mutation profile. During the pilot, a malformed provider attribute caused
Spark's asynchronous `__after_verify__/1` to exit the Covenant worker with
`UndefinedFunctionError: nil.__struct__/0`. The fork did not record an invalid
verdict or finish that job. The partial 21-file run is not a complete result.
The 20-file profile still tests fresh DSL compilation, compiler macros, inline
Actions, extension lowering, and generated helpers. Provider declarations and
metadata validation remain covered by public contract tests and line coverage.
This is a tool limit, not an accepted behavior gap. No mutation score is claimed
for the excluded provider file.

## Protected surface

The canonical value has `module`, `vsn`, `name`, `description`, `schema`,
`plugins`, `routes`, and `metadata`. Definitions have nil `id` and `state`.
Instances add a nonempty `id` and a complete state map.

The entry points are `Jido.Agent.new/1`, `new!/1`, `instantiate/1,2`,
`instantiate!/1,2`, `validate/1`, `validate_definition/1`, `validate_instance/1`,
`definition?/1`, `instance?/1`, `definition/1`, `complete_schema/1`,
`complete_schema!/1`, `set/2`, `cmd/2,3`, `handle_signal/2`, and `use Jido.Agent`.
Generated modules retain `definition/0`, `vsn/0`, `domain_schema/0`,
`complete_schema/0`, `new/0,1`, `new!/0,1`, `cmd/2,3`, `route_action!/1`, and
exposed `<name>_signal/1,2` helpers. Codec encoding/decoding, public Turn
constructors and validation, and `Jido.Agent.Extension.lower/3` are also tested.
Private compiler exports, generated inline module names, and runtime records
remain open to change.
