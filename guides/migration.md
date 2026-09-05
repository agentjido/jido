# Migrate from Jido V2 to the V3 candidate

This branch transfers prepared source
`jido_v3@bf6c9fbec569cb6438b6a1629a2768058d439d1f` into core Jido.
The public names remain `Jido.Agent` and `Jido.AgentServer`. This is a major API
change. It does not provide source compatibility with V2 or an automatic storage
conversion. The candidate remains local until a separate publication decision.

## Port a command

| V2 use | V3 use |
| --- | --- |
| Module `new/1` returns a struct | `new/1` returns a tagged result; `new!/1` returns a struct or raises |
| Generic `Agent.new` combines configuration and instance data | Build a neutral definition, then call `Agent.instantiate/2` |
| Instruction or Action input to `cmd` | Send a `Jido.Signal` that selects one Action or Flow |
| `{agent, directives}` from `cmd` | `{:ok, candidate, directives}` or `{:error, reason}` |
| State patches and StateOps | Return complete candidate state; use `context.agent_state` as the base |
| Strategy, FSM Strategy and before/after command hooks | Action/Flow execution and explicit V3 Plugin callbacks |
| `signal_routes` | Definition `routes` or Spark `routes` block |
| Context read from old Agent/Server structs | `context.agent_id`, `context.agent_state`, and `context.signal` |
| Await/status polling facade | Live calls, separate requests, readiness and cancellation APIs |
| `Jido.whereis` facade | `Jido.whereis_agent(instance, id, partition: partition)` |
| Startup `initial_state` | Retained for Server options; instance constructor uses `state` |

The [README example](../README.md#example) contains a complete Action, Agent,
Signal helper, direct call, and live call. [Agent state](agents.md) describes
schemas and optional state-size limits. Limits use external term bytes and
include Plugin state. A failed candidate leaves the committed revision unchanged.

## Port effects and Plugins

Actions and Flows can perform I/O before commit. Validation or storage failure
cannot undo that I/O. Define external idempotency and retry rules.
Directives run after commit. A directive failure keeps that commit and stops the
rest of its batch. A live call can therefore succeed before a later effect fails.

Port Plugin manifests, mounts, requirements, config helpers, routes, and old
callbacks to `Jido.Plugin.Spec` and the [V3 callbacks](plugins.md). Plugins own
one declared state key and their typed directives. Optional child specifications
start owned runtimes. A stateless dispatch Plugin receives a nil runtime.
V2 `DirectiveExec` implementations and `directive_handler` are removed.

## Port lifecycle and composition

Use instance and partition scope consistently. Server attachment, detach, touch,
idle timeout, child ownership, local/remote placement, and hibernate/thaw remain.
The public V2 InstanceManager and WorkerPool APIs are removed. There is no
pre-warmed checkout pool. Use explicit [bounded workers](worker-pools.md).

The Pod API, mutable graph planner, Pod state, and mutation directives are
removed. Use static [Topology](orchestration.md), owned children, or the explicit
Fixed/Elastic Group applications. Arbitrary live graph mutation is outside this
release. A remote disconnect does not prove death. Cluster-exclusive ownership
is not implemented; DIST-03 is the only approved excluded test.

## Port stored data

Use `Jido.Persistence` with a binary adapter and atomic compare-and-swap.
Keys begin with `jido:agent:v1:` and include instance, module, partition, and ID.
Load validates the outer record, restored identity, complete schema, and recursive
portability. Old Actor and V2 envelopes are rejected. A format rename alone is
not a valid conversion.

For existing data, keep an offline backup, decode it with the old application,
construct and validate a V3 instance, then save through the V3 adapter. Define
application-specific conversion for Plugin state and pending work. Verify identity,
partition, history, pending work IDs, and retry attempts before activation.
Do not run old and new writers against the same logical records during conversion.
No converter is included in this candidate.

An uncertain write stops the writer before another Action evaluates. A confirmed
conflict remains a failed commit. New activation loads authoritative state.
Without an adapter, local RuntimeStore checkpoints support abnormal restart only
while the instance remains alive. They do not survive loss of the instance or VM.

The old Storage checkpoint/Thread API and Thread append stores are removed.
Standalone Thread values remain. Redis TTL remains an adapter option. File
storage has one BEAM owner per directory. See [storage limits](storage.md).

## Other removed interfaces

| Removed V2 feature | Supported direction and limit |
| --- | --- |
| Sensor behavior, Sensor structs and built-in Sensor modules | Explicit input Plugins; SensorManager requires a callback port |
| Native cron directives and Agent schedules | Scheduler and Heartbeat Plugins; explicit occurrence acknowledgement |
| Discovery service | Explicit module lists and trusted Codec Registry |
| Identity profile and evolution framework | Application-owned identity policy; security examples do not replace profile APIs |
| Integrated Memory spaces | Application state, history and compaction; no Memory API adapter |
| Thread Agent/Plugin integration | Standalone Thread values and application-owned persistence |
| Old observation event/configuration contracts | V3 lifecycle, Turn, commit, directive and safe error fields |
| Built-in control/status/lifecycle Actions | Explicit application Actions and supported runtime directives |

The [file and test register](../docs/migration/legacy-dispositions.json) records
all 278 baseline files and all 2,299 baseline test identities. Each entry names
its current checks or its retired interface and guide. The original source remains
in Git at `a31b74306d4498ee47732c18b993abd4c26542bd`.

## Downstream packages and checks

Existing `jido_ai` consumers use the removed Strategy and Server State contracts.
Existing `jido_browser` code uses the old Plugin contract. They require a separate
port. Core does not claim drop-in compatibility and this migration does not edit
those packages. Deterministic LLM and Factory examples in core use the V3 API.
They do not validate model quality or a paid provider session.

All 52 fixtures, shared support, supporting core tests, and ten application
scenarios are required. Run the full command from [testing](testing.md).
The [execution record](../docs/migration/10-execution-record.md) lists tested
source hashes and results. The seed campaign, continuous workload, runtime
matrix, coverage, lint, Dialyzer, docs, and fresh package consumer must pass before
local beta QA is complete.

The documents under `docs/design` are pending proposals. Their Ref facade,
Plugin pipeline, and replacement persistence architecture are not part of this
migration. Use the current API docs and the implemented contracts above.
