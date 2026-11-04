# NewJido

> [!WARNING]
> This repository is an experiment. It is not the current Jido release, a
> supported package, or a complete source of Jido documentation. APIs, module
> ownership, and project structure can change while the consolidation work is
> in progress.

This experiment consolidates the four core Jido repositories, `jido`,
`jido_action`, `jido_signal`, and `jido_ai`, into one Mix project and one OTP
application. The first source port is complete. The project is now testing and
refining the module boundaries that became visible after the packages moved
together.

Many release-quality parts are missing, incomplete, or out of date. These
include:

- complete user and module documentation;
- tutorials and a reviewed example set;
- migration guidance from the four separate packages;
- final package, version, and release configuration;
- a complete public API and compatibility review; and
- final performance baselines across the supported runtime matrix.

Do not use this repository as the official guide for a released Jido version.
The current focus is architecture and quality backpressure. Documentation and
release preparation will follow after those boundaries are stable.

The main work is:

- organize code by `Jido.*` ownership instead of old package boundaries;
- keep one `Jido.Application` composition root;
- use `Jido.Flow` as the Agent behavior boundary;
- compile Actions and Flows to Runic workflows; and
- keep Joi schemas as the Jido data boundary.

The surrounding NewJido workspace keeps the architecture and consolidation
decisions in `docs/aspirational-module-dependency-map.md`.

Use the [documentation index](docs/README.md) for project documents, required
fixed paths, and material that still needs review.

## Local checks

```sh
mix deps.get
mix test
mix test.ci
mix test.all
mix test.contracts
mix test.authoring
mix test.examples
mix test.property
mix test.fuzz
mix test.system
mix test.load
mix test.peer
mix test.bench
mix quality
mix quality.coverage
mix quality.report
mix reach.check --arch --smells
```

`mix quality.coverage` measures the package, all active Covenant components, and each required offline suite. Run it
before `mix quality.report`. The report writes JSON and text evidence under `tmp/quality/` and fails when a required
suite, obligation, component proof, coverage rule, or stability record is not satisfied. Live provider and external
service checks are separate opt-in commands.

`mix quality` blocks highest-priority Credo findings, compile warnings,
Dialyzer errors, ExDNA errors, Reach architecture errors, and formatting
errors. It also prints the full strict Credo backlog as advisory output.
Dialyzer checks new warnings against the line-specific baseline in
`.dialyzer_ignore.exs` and rejects unused baseline entries.
ExDNA reports all clone groups and fails above the current 17-clone baseline.

Run external services and the paid provider only when you explicitly select
them:

```sh
mix test.services
JIDO_LIVE_OPENAI_API_KEY=... mix test.live
```

The live command requires a dedicated test key. See `test/external/README.md`
and `test/external/jido_ai/README.md` for setup and cleanup rules. The CI
workflow runs each required offline surface as a named job. Its
scheduled or manual extended jobs run longer fuzz, load burn-in, and benchmark
checks. Service and live jobs are manual only.

The live graph-first example makes a paid model call. It starts a Jido instance,
runs the canonical ReAct Flow in an AgentServer, calls two Actions in one tool
round, and checks the committed Session.

```sh
mix run examples/00_quick_start/00_03_live_react/live_react.exs
```

The default model is `openai:gpt-4o-mini`. Use `JIDO_LIVE_MODEL` and
`JIDO_LIVE_PROMPT` to change the model and prompt.

## Runic ReAct memory benchmark

[`test/perf/jido_ai/react_memory.exs`](test/perf/jido_ai/react_memory.exs) is one self-contained
reproduction and benchmark for the canonical graph-first ReAct path. It does
not call a model provider. A deterministic local inference client emits known
tool calls. A local Action returns an empty payload.

The default `quick` profile is one bounded iterative case for local checks. The
`base` profile is the shared comparison case for Jido and Runic work. It removes
model, network, payload, concurrency, and AgentServer effects. It compares two
orchestration strategies.

The benchmark-local `recursive` strategy preserves the former core path:

```text
Jido Agent.cmd/3
  -> Jido.Exec
  -> Runic.Workflow.execute/3
  -> dynamic ReAct invoke graphs
```

The production `iterative` strategy is now `Jido.AI.Reasoning.ReAct` and uses
this path:

```text
Jido Agent.cmd/3
  -> one fixed Jido iterate graph
  -> one ReAct transition Action per model round
  -> the same loop nodes for the next round
```

The base profile has these fixed defaults:

| Setting | Value |
| --- | --- |
| Strategies | `recursive` and `iterative` |
| Execution | Direct, in-memory Runic workflow |
| Tool calls | One serial call per ReAct round |
| Tool result payload | 0 bytes |
| Maximum concurrency | 1 |
| Round counts | 1, 3, and 5 |
| Isolation | One new BEAM VM for each round count |

With Runic `0.1.0-alpha.13`, the recursive one-round and three-round cases
finish. The recursive five-round case reaches the canonical identity item limit
while it processes 137,659 items at path `[:value, 1]`. The iterative strategy
finishes all three cases.

One local comparison produced these peak process-memory changes:

| Rounds | Recursive | Iterative | Iterative / recursive |
| ---: | ---: | ---: | ---: |
| 1 | 7.95 MiB | 3.26 MiB | 0.41x |
| 3 | 36.29 MiB | 3.13 MiB | 0.09x |
| 5 | 64.98 MiB, then error | 6.89 MiB | 0.11x |

The production iterative strategy also completed eight tool rounds with 9.35
MiB of peak process-memory growth.

These values vary by host. The growth shape and execution outcome are the
important results.

The script captures the recursive execution error as benchmark data and exits
normally. The benchmark runner does not fail.

### What the experiment proves

The former ReAct design recursively added a new ModelRound and tool Flow to the
active Runic workflow. Every round also carried the prior Jido Frame. Replacing
that recursive expansion with a fixed loop removes the identity-limit failure
and most of the memory growth.

The core implementation preserves the normal request and response contract,
parallel tools, durable review waits, model and tool counts, Session entries,
output guards, retry routing, and budget routing.

One loop transition calls the existing ReAct Actions inside one outer Runic
Action. Each tool batch runs as a short-lived Runic Flow with explicit parallel
tool nodes. The inner Flow is discarded after the round, so it cannot expand
the active outer graph. An approved review resumes through another fixed loop.

The remaining boundary is checkpoint detail. Inner model work and a complete
tool batch belong to the outer transition checkpoint. They do not have separate
checkpoints in the active outer workflow.

The benchmark keeps the former recursive Flow in the benchmark file only. It is
not a second library implementation.

### Run and capture the base case

Run the base profile in the production Mix environment:

```sh
JIDO_MEMORY_BENCH_PROFILE=base mix bench
```

Save one report that you can attach to an issue or send to another developer:

```sh
JIDO_MEMORY_BENCH_PROFILE=base mix bench 2>&1 | tee runic-react-memory.txt
```

The report records the Jido Git revision, dirty-worktree state, Runic version,
Elixir version, OTP version, system architecture, scheduler count, and memory
sample interval. For each isolated case, it reports:

- elapsed time;
- peak process, total, binary, and ETS memory above the forced-GC baseline;
- final process-memory change;
- retained Agent and Session term sizes;
- committed Thread entry count;
- model, tool-round, and tool-call count checks; and
- the Runic error and stack trace when a case fails.

The report also shows the compiled Runic graph component count, build-log entry
count, shared size, and flat size. It compares the peak process memory of the
three-round and five-round cases with the one-round case.

The iterative base case has two success conditions:

1. All three iterative round counts finish without a canonical identity limit.
2. Peak memory grows in proportion to the added rounds. It must not make a
   large jump between adjacent cases.

### Run the expanded profile

The expanded profile keeps the same deterministic model and tool. It adds the
managed AgentServer path, four-call workloads, parallel execution, and a small
tool payload:

```sh
JIDO_MEMORY_BENCH_PROFILE=expanded mix bench
```

This profile runs 18 recursive-strategy isolated cases:

- direct and managed execution;
- 1, 3, and 4 rounds; and
- serial, constrained, and parallel workloads.

The workloads are:

| Workload | Tool calls per round | Maximum concurrency |
| --- | ---: | ---: |
| `serial` | 1 | 1 |
| `constrained` | 4 | 1 |
| `parallel` | 4 | 4 |

### Configuration

| Environment variable | Meaning |
| --- | --- |
| `JIDO_MEMORY_BENCH_PROFILE` | `quick`, `base`, or `expanded` |
| `JIDO_MEMORY_BENCH_STRATEGIES` | Comma-separated `recursive` or `iterative` strategies |
| `JIDO_MEMORY_BENCH_MODES` | Comma-separated `direct` or `managed` modes |
| `JIDO_MEMORY_BENCH_ROUNDS` | Comma-separated round counts from 1 through 8 |
| `JIDO_MEMORY_BENCH_WORKLOADS` | Comma-separated workload names |
| `JIDO_MEMORY_BENCH_PAYLOAD_BYTES` | Bytes returned by each tool call, from 0 through 1,000,000 |
| `JIDO_MEMORY_BENCH_REPEATS` | Number of isolated runs for each case |
| `JIDO_MEMORY_BENCH_SAMPLE_MS` | VM memory sampling interval |
| `JIDO_MEMORY_BENCH_OUTPUT` | `markdown` or `json` |

Peak values come from `:erlang.memory/0`. Retained values come from
`:erts_debug.size/1` and `:erts_debug.flat_size/1`. These are VM-level
diagnostics, not operating-system resident-set measurements. Use the same
Elixir, OTP, Runic version, scheduler count, Mix environment, and host when you
compare two commits.

