# NewJido

This repository is an exploration of one consolidated Jido project. It brings
`jido`, `jido_action`, `jido_signal`, and `jido_ai` into one Mix project and one
OTP application. It is a working architecture branch, not a published package.

The main work is:

- organize code by `Jido.*` ownership instead of old package boundaries;
- keep one `Jido.Application` composition root;
- use `Jido.Flow` as the Agent behavior boundary;
- compile Actions and Flows to Runic workflows; and
- keep Joi schemas as the Jido data boundary.

The surrounding NewJido workspace keeps the architecture and consolidation
decisions in `docs/aspirational-module-dependency-map.md`.

## Local checks

```sh
mix deps.get
mix test
mix reach.check --arch --smells
```

The live graph-first example makes a paid model call. It starts a Jido instance,
runs the canonical ReAct Flow in an AgentServer, calls two Actions in one tool
round, and checks the committed Session.

```sh
mix run examples/00_graph_first/live_react.exs
```

The default model is `openai:gpt-4o-mini`. Use `JIDO_LIVE_MODEL` and
`JIDO_LIVE_PROMPT` to change the model and prompt.

## Runic ReAct memory benchmark

[`bench/react_memory.exs`](bench/react_memory.exs) is one self-contained
reproduction and benchmark for the canonical graph-first ReAct path. It does
not call a model provider. A deterministic local inference client emits known
tool calls. A local Action returns an empty payload.

The default profile is the shared base case for Jido and Runic work. It removes
model, network, payload, concurrency, and AgentServer effects. The execution
path is:

```text
Jido Agent.cmd/3
  -> Jido.Exec
  -> Runic.Workflow.execute/3
  -> dynamic ReAct invoke graphs
```

The base profile has these fixed defaults:

| Setting | Value |
| --- | --- |
| Execution | Direct, in-memory Runic workflow |
| Tool calls | One serial call per ReAct round |
| Tool result payload | 0 bytes |
| Maximum concurrency | 1 |
| Round counts | 1, 3, and 5 |
| Isolation | One new BEAM VM for each round count |

With Runic `0.1.0-alpha.13`, the one-round and three-round cases finish. The
five-round case reaches the canonical identity item limit while it processes
137,659 items at path `[:value, 1]`. This is the base failure. A Runic change
can be tested against the same input without a model provider or a paid call.
The script captures this execution error as benchmark data and exits normally.
It does not mean that the benchmark runner failed.

### Run and capture the base case

Run the base profile in the production Mix environment:

```sh
mix bench
```

Save one report that you can attach to an issue or send to another developer:

```sh
mix bench 2>&1 | tee runic-react-memory.txt
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

The base case has two success conditions:

1. All three round counts finish without a canonical identity limit.
2. Peak memory grows in proportion to the added rounds. It must not make a
   large jump between adjacent cases.

### Run the expanded profile

The expanded profile keeps the same deterministic model and tool. It adds the
managed AgentServer path, four-call workloads, parallel execution, and a small
tool payload:

```sh
JIDO_MEMORY_BENCH_PROFILE=expanded mix bench
```

This profile runs 18 isolated cases:

- direct and managed execution;
- 1, 3, and 5 rounds; and
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
| `JIDO_MEMORY_BENCH_PROFILE` | `base` or `expanded` |
| `JIDO_MEMORY_BENCH_MODES` | Comma-separated `direct` or `managed` modes |
| `JIDO_MEMORY_BENCH_ROUNDS` | Comma-separated round counts from 1 through 16 |
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

