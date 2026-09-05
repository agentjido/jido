# Code replacement map

Status: proposed. The [inventory](file-inventory.csv) is a comparison of tracked
files, not a dead-code proof. `review-remove` means that the path is absent from
the prepared Agent donor. Remove it only after its behavior
and callers have a recorded disposition.

## Replacement units

| Unit | Core paths to refactor | Donor paths to transfer | Required behavior and test work |
| --- | --- | --- | --- |
| Agent value and execution | `lib/jido/agent.ex`, `agent/command.ex`, `agent/state.ex` | `agent.ex`, `agent/{command,command/runner,state,turn,turn/outcome,validation}.ex` | Complete state, schema validation, reserved context, direct/live agreement, failed-output isolation |
| Authoring | Macros and construction code in `agent.ex` | `agent/authoring.ex`, `builder.ex`, `codec.ex`, `codec/*`, `dsl/*`, `interface.ex` | Spark Agent block, routes, generated functions, inline Action targets, definition/instance separation, equivalent authoring forms |
| Live server | `agent_server.ex`, `agent_server/*` | `agent_server.ex`, `agent_server/*` | Admission, execution tasks, ordering, timeout, cancellation, commit, directive dispatch, startup, stop, restart, ownership and cleanup |
| Directives | `agent/directive.ex`, old executor protocol and implementations | `agent/directive.ex`, `agent_server/directive_runtime.ex`, directive context | Preserve typed validation and complete batch rejection; use `SpawnAgent`; move scheduler/sensor behavior to Plugins |
| Plugin contract | `plugin.ex`, `plugin/spec.ex`, remaining old Plugin support | `plugin.ex`, `plugin/{spec,init,signal_context,directive_context,codec}.ex` | Runtime-free and runtime-backed dispatch, state ownership, declaration validation, readiness, restart, pure command preparation |
| Built-in capabilities | Scheduler, Sensors, built-in actions | `plugin/{audit,bus,dispatch,heartbeat,scheduler,sensor_manager}*` | Real Bus delivery, scoped lookup, timer replacement, task supervision, durable occurrence identity, resource restart |
| Instance/application | `lib/jido.ex`, `application.ex`, `config/defaults.ex` | Donor equivalents | Keep `use Jido` and Agent startup names; update supervision, registry, partitions, runtime store and persistence options together |
| Persistence | `persist.ex`, `storage.ex`, `storage/*`, keyed lifecycle hooks | `persistence.ex`, `persistence/{adapter,ets,file,redis}.ex`, server runtime checkpoint | CAS, revision, restore, nested identity, recursive load validation, uncertain write authority, hibernate/thaw |
| Observation/error handling | `error.ex`, `observe*`, `telemetry*`, `debug.ex`, `tracing/*` | Donor equivalents plus `telemetry/agent.ex` | Safe projection, causation, bounded data, terminal outcomes, observer failures, remote traces |
| Topology | No direct equivalent; old Pod is not the same API | `topology.ex`, `topology/*` | Static construction, DSL/Builder/JSON, groups, binding/import/export, deterministic IDs, bounded startup, repair and full shutdown |
| Utility/data values | `id.ex`, `util.ex`, `util/deep_merge.ex`, `thread.ex`, `thread/{entry,entry_normalizer}.ex`, `runtime_store.ex` | Corresponding files | Keep unchanged files unchanged; inspect same-path differences before choosing donor content |

All donor paths refer to `bf6c9fb` and are under `lib/jido/`. Source paths and proposed
destinations are explicit in the CSV. Do not replace the whole `lib` directory
without reviewing the removal list.

## Removal and replacement register

The comparison finds 82 current core `lib` files without a mapped donor path.
They form these work groups. Their tests must be assigned before removal.

| Core code | Proposed disposition | Replacement/proof |
| --- | --- | --- |
| `agent/strategy*`, `agent/state_op.ex`, `agent/state_ops.ex` | Remove the V2 execution/state-operation engine during the complete cutover | Action/Flow plus full candidate state. Re-express ordering, invalid-state, error and state-isolation tests |
| `agent/default_plugins.ex`, `agent/schedules.ex` | Remove implicit defaults and compile-time scheduling integration | Explicit Plugin declarations; scheduled signals and no-plugin Basic case |
| `plugin/{config,instance,manifest,requirements,routes,schedules}.ex` | Replace the old declaration and callback machinery | New Plugin Spec/Codec and contract tests. Document options and callback migration |
| `agent_server/directive_exec.ex`, `directive_executors.ex` | Replace the dispatch protocol | New DirectiveRuntime and owned Plugin dispatch; audit custom `jido_ai` directive implementations |
| `agent_server/error_policy.ex`, `signal_router.ex`, `state/lifecycle.ex`, `status.ex` | Replace or retire after public-result mapping | Server options/runner/state/status behavior; preserve structured failure and public inspection assertions |
| `agent_server/lifecycle*`, `stop_child_runtime.ex` | Replace V2 keyed/child lifecycle machinery | New server ownership and runtime checkpoint; restart, stale PID, partition and stop tests |
| `agent_server/sensor_lifecycle.ex`, old cron/scheduled/sensor-exit signals | Replace V2 Sensor coupling | Scheduler, Heartbeat, SensorManager Plugins; prove resource start, replacement and stop |
| `scheduler.ex`, `scheduler/job.ex`, `agent/directive/{cron,cron_cancel}.ex` | Replace wrappers; keep the patched SchedEx dependency | Scheduled Signals and durable scheduling cases. Preserve cancellation and shutdown behavior |
| `sensor.ex`, `sensor/*`, `sensors/*` | Remove old public Sensor implementation only with migration documentation | Explicit input Plugins. `SensorManager` is not source-compatible with every old Sensor callback |
| `persist.ex`, `storage.ex`, `storage/*` | Replace with the selected V3 persistence API and format | Mapped adapters and storage tests; explicit old-record rejection/conversion, TTL and concurrency limits |
| `agent/instance_manager*`, `agent/worker_pool.ex` | Remove old managed/pool implementation after capability review | Registry/instance lifecycle, keyed identities, Bounded Workers, Topology keyed accounts; separately document lost idle/attachment/pool behavior |
| `pod.ex`, `pod/*` | Retire the old Pod API | Child Lifecycle, hierarchy, Fixed/Elastic Group and Topology prove selected replacements. Live Pod mutation has no automatic equivalent |
| `await.ex` and related `Jido` facade delegates | Audit public functions; retain a small adapter only for contracts that still have meaning | Cancellation, child lookup and completion examples. Do not keep a V2 polling layer that assumes removed state shapes |
| `actions/{control,lifecycle,scheduling,status}.ex` | Retire or rewrite per public capability | Directives and explicit application Actions. Inspect every old action export before removing it |
| `discovery.ex` and facade listing delegates | Separate retirement decision | Donor has no equivalent discovery service. Remove startup and docs references together if retired |
| `agent/identity*` | Retire old built-in identity framework unless a retained contract is named | Donor identity/secure-signal scenarios prove verification and encryption, not the old profile/evolution API |
| `memory.ex`, `memory/*` | Retire old integrated Memory API only with a capability note | Application state and LLM history/compaction. Multi-space memory is not proven by these examples |
| `thread/{agent,plugin,store}.ex`, `thread/store/*` | Remove runtime integration; retain standalone Thread values | Conversation History, ReAct integration, compaction and restore |
| `observe/event_contract.ex`, `telemetry/config.ex` | Compare and replace event/config validation | Explicit Agent telemetry map; transport-safety tests and downstream event consumers |

Old public features without a proven replacement remain open scope decisions.
They cannot disappear solely because the donor lacks their files. The final
beta migration guide must identify removals and any replacement package.

## Tests and support code

Every core test file appears in the inventory. Classify each as:

1. Keep unchanged when it checks an unchanged utility or data contract.
2. Rewrite against Agent names and the new API while preserving its behavior
   assertion, such as state isolation, error paths, delivery ordering or cleanup.
3. Replace with named donor acceptance tests and record that mapping.
4. Retire only with the public feature it tested and state why.

Do not infer that all old tests are obsolete. In particular, preserve safe
normalization, validation-path transport, partition isolation, shutdown races,
storage fault behavior, and state-size protections from current main.

Port test support with its dependent tests. `llm_sdk_case.ex` implements the
example Adapter behaviour. Remote, recovery, schedule, trace and Factory
fixtures reference `Jido.Examples` modules. Copying all `test/support` before
those modules exist can break test compilation. Each commit must include the
source dependency closure for its tests, not only files ending in `_test.exs`.

The 10 donor integration directories each contain implementation fixtures in
`example_test.exs` and scenario tests. Preserve both. They are not duplicates
of the 52 catalog fixtures. Research tests remain accounted for even where
they expose a deliberately unsupported capability.

## Dependencies, build, documentation, and packaging

The prepared implementation includes the source repairs. Copy those bytes
with M02 and preserve their checks in M03, M04, M07, and M11. Do not repeat the
Actor rename. The [preparation record](07-prepared-donor.md) lists each change.
Review `scripts/migration-check.py`, `scripts/migration-manifest.py`, and
`test/support/migration_formatter.ex` for the M01 acceptance tooling. Adapt
donor-specific report paths explicitly. Test startup preloads modules and local
ReqLLM metadata; retain the needed order without reducing concurrency.

- Core currently locks `jido_action` beta.2. The donor pins beta.6 and uses
  inline Actions, expression helpers and Flow APIs from it. Adopt that fixed
  dependency set for parity, then assess dependency updates in a separate commit.
- Add Spark for Agent authoring. Keep `jido_signal` beta.2 and patched SchedEx
  1.2.1 while establishing the baseline. Remove `poolboy` only after its callers
  are gone. Re-resolve the lockfile deliberately; do not copy unrelated cache state.
- Factory uses ReqLLM and Dotenvy. Its automated tests use local HTTP/SSE
  adapters. Decide whether these are example-only build dependencies or remain
  optional runtime dependencies. Test a core consumer that does not install
  either package. Do not make AI services required to start Jido.
- Update `.formatter.exs`, compile paths and Spark imports. Avoid shipping
  example-only providers accidentally through the package's current `lib` glob.
  Record any example relocation in the manifest and provide a runnable command.
- Preserve core GitHub URLs and package identity. The donor still reports version
  `2.3.3`; it is not already a V3 release. Change the version only in beta QA.
- Reconcile the package file list with files that actually exist in core. The
  donor removed a missing `usage-rules.md` entry; this does not authorize removal
  of a core guide.
- Update README, `usage-rules.md`, guides, docs module groups, `AGENTS.md` and
  `test/AGENTS.md` with the selected contract. Remove broken V2 links and document
  replacements. Import relevant design notes with Agent names and clear proposal
  status; do not label unimplemented structs or callbacks as current APIs.
- Keep diagnostic logs separate from runnable examples. Preserve the current
  archive as historical documents; do not count its removed sketches as working
  fixtures. Do not edit `CHANGELOG.md`; release notes come from commit history.
- Add explicit CI example/integration jobs. A default `mix test` job alone
  does not prove the catalog. Keep long soak and optional provider runs separate.

## Main-branch changes to carry forward deliberately

`main` has seven commits outside the fixed spike. Do not merge them blindly
after the rewrite. Assess each behavior or configuration change at its new path.

| Commit | Work in the migration |
| --- | --- |
| `99aa07cc` state-size budgets | Port the optional serialized-state budget and tests to construction, transition, restore and live commit. Do not apply limits only to an old StateOps path |
| `2d2ab51d` validation error transport paths | Compare donor `Jido.Error`; port missing path normalization and hostile-input tests |
| `8f8f9e49` remove legacy work tracker | Keep the tracker removed; do not restore scripts from an older snapshot |
| `7dc12069` routing guide corrections | Preserve the corrected routing meaning when rewriting guides |
| `2b05de80` telemetry_metrics update | Resolve deliberately in the dependency/maintenance commit |
| `d30c5f7a` CI runner migration | Preserve the current CI infrastructure where applicable |
| `adf3e058` dependency updates | Compare lockfiles and keep applicable fixes; avoid reverting unrelated maintenance |

Recheck `origin/main` before the final series is published. New changes after
the recorded revision need the same behavior-based review.
