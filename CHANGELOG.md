# CHANGELOG

<!-- changelog -->

## [v3.0.0-beta.1](https://github.com/agentjido/jido/compare/v3.0.0-beta.1...v3.0.0-beta.1) (2026-09-14)
### Breaking Changes:

* agent: replace the V2 runtime with the V3 command contract by mikehostetler

* install: remove Igniter integration by mikehostetler

* migrate Signal APIs to v3 by mikehostetler

* migrate Agent runtime to jido_action v3 by mikehostetler

* convert Action schemas to Zoi by mikehostetler



### Features:

* topology: retain accepted targets and settle owned agents by mikehostetler

* persistence: add conditional S3 adapter (#369) by mikehostetler

* add isolated plugin preparation inputs by mikehostetler

* observability: add optional OpenTelemetry API mapping by mikehostetler

* persistence: merge Bedrock adapter by mikehostetler

* persistence: add Bedrock adapter by mikehostetler

* persistence: merge Ecto adapter by mikehostetler

* persistence: add Ecto adapter by mikehostetler

* topology: support additive live targets by mikehostetler

* agent_server: add explicit live upgrade boundary by mikehostetler

* telemetry: align semantic observation by mikehostetler

* error: close public code registry by mikehostetler

* topology: integrate plugin planning by mikehostetler

* topology: align runtime ownership seam by mikehostetler

* jido: add ref-first instance facade by mikehostetler

* agent_server: align activation runtime by mikehostetler

* persistence: add durable record lifecycle by mikehostetler

* commit: enforce write authority boundary by mikehostetler

* plugin: split owner facet contracts by mikehostetler

* turn: fix source signal selection by mikehostetler

* agent: add stable agent reference by mikehostetler

* error: align public failure contracts by mikehostetler

* agent: align authoring parity seam by mikehostetler

* agent: align v3 agent contract by mikehostetler

* agent: support guarded inline route clauses by mikehostetler

* topology: use the agent authoring host by mikehostetler

* agent: support AI profile routes by mikehostetler

* topology: support authoring extensions by mikehostetler

* add default instance lifecycle helpers by mikehostetler

* agent: add static authoring extensions by mikehostetler

* expose scheduler cadence and topology repair controls by mikehostetler

* topology: compose and supervise Agent systems by mikehostetler

### Bug Fixes:

* bus: keep durable delivery off Client mailbox by mikehostetler

* runtime: wait for prior children before Jido replacement by mikehostetler

* runtime: verify Bus subscriptions before Topology readiness by mikehostetler

* telemetry: emit one terminal event per semantic span by mikehostetler

* plugin: enforce owner contracts and normalize once for encoding by mikehostetler

* runtime: treat hive identifiers as literal ETS values by mikehostetler

* examples: align basic learning path by mikehostetler

* isolate quality tooling runtime by mikehostetler

* align hardening type contracts by mikehostetler

* topology: type error location failures by mikehostetler

* topology: reject mixed startup locations by mikehostetler

* agent: reuse normalized plugin specs by mikehostetler

* topology: preserve host options in macro calls by mikehostetler

* agent-server: verify deferred child identity by mikehostetler

* agent-server: harden lifecycle and runtime boundaries by mikehostetler

* scheduler: harden durable runtime behavior by mikehostetler

* review: address topology hardening findings by mikehostetler

* persistence: validate adapters and contain timeouts by mikehostetler

* observe: make telemetry boundaries total by mikehostetler

* tracing: harden dual-format propagation by mikehostetler

* plugin: harden runtime contracts by mikehostetler

* harden agent checkpoints and threads by mikehostetler

* topology: unify authoring validation contracts by mikehostetler

* topology: harden runtime ownership and readiness by mikehostetler

* agent: enforce constructor and codec error contracts by mikehostetler

* plugin: preserve structured state schema errors by mikehostetler

* plugin: keep runtime lookup responsive during restart readiness by mikehostetler

* deps: update Jido Hex releases and supervisor routing by mikehostetler

* ci: keep example tests out of CI (#363) by mikehostetler

* ci: repair shared V3 validation failures (#362) by mikehostetler

* preserve Agent startup errors and apply Flow copy fix by mikehostetler

* scheduler: use patched SchedEx release by mikehostetler

### Performance:

* topology: keep authoring paths linear by mikehostetler

* codec: avoid duplicate set storage during derivation by mikehostetler

* codec: collect Agent registry entries in one accumulator by mikehostetler

* agent: build routes with canonical reversed storage by mikehostetler

* observe: reuse synchronous span start values by mikehostetler

* codec: scan document maps with an iterator by mikehostetler

* scheduler: limit delivery task capture by mikehostetler

* persistence: reuse the default ETS table name by mikehostetler

* state: scan keyword merge input once by mikehostetler

* state: read the module budget once per check by mikehostetler

* thread: filter one kind without a membership list by mikehostetler

* codec: reuse validated neutral definitions during encode by mikehostetler

* command: check reserved keys without copying valid context keys by mikehostetler

* server: limit admission task capture to Plugin specs by mikehostetler

* audit: reuse the count when trimming empty updates by mikehostetler

* audit: keep bounded buffers for empty updates by mikehostetler

* audit: read the clock only for default timestamps by mikehostetler

* audit: generate record IDs only when absent by mikehostetler

### Refactoring:

* core: standardize Signal identities and message contracts by mikehostetler

* runtime: share child lookup and remove duplicate owner watch by mikehostetler

* topology: build dependency layers in linear passes by mikehostetler

* plugins: trim built-in delivery and audit paths by mikehostetler

* persistence: share checkpoint conversion and write options by mikehostetler

* turn: keep source signal on selected turn by mikehostetler

* agent: tighten authoring and instance boundaries by mikehostetler

* core: trim repeated validation and error rules by mikehostetler

* instance: share namespace claim creation by mikehostetler

* plugin: check owned state keys in one pass by mikehostetler

* state: simplify portable map validation by mikehostetler

* bus: use keyword defaults for instance scope by mikehostetler

* plugin: stop runtime processes without liveness prechecks by mikehostetler

* plugin: collect runtime child specs in linear time by mikehostetler

* runtime: share execution cancellation replies by mikehostetler

* runtime: match execution callback tokens explicitly by mikehostetler

* runtime: validate spawn owner monitors once by mikehostetler

* runtime: use the GenServer child specification by mikehostetler

* identify agent server owned work by mikehostetler

* extract agent server persistence by mikehostetler

* extract agent server runtime policy by mikehostetler

* extract agent server admission and views by mikehostetler

* move agent server api to facade by mikehostetler

* separate agent server facade and runtime by mikehostetler

* tighten agent server runtime boundaries by mikehostetler

* normalize v3 verification boundaries by mikehostetler

* tighten v3 runtime boundaries by mikehostetler

* agent: align directive lifecycle names by mikehostetler

* agent: finish simplification pass by mikehostetler

* Jido Plugin Tests and Update Callbacks by mikehostetler

* examples: tighten basic learning path by mikehostetler

* agent: remove state size budget by mikehostetler

* config: colocate defaults with owners by mikehostetler

* agent: generalize extension route targets by mikehostetler

* thread: remove deprecated data helpers by mikehostetler

* id: delegate UUID generation to signals by mikehostetler

* agent: share authoring validation and route targets by mikehostetler

* number application examples and matching tests by mikehostetler

* move examples out of lib and unify test tags by mikehostetler

* remove unused core helpers by mikehostetler

* topology: keep timeout state in active jobs (#358) by mikehostetler

* agent_server: share task completion cleanup (#357) by mikehostetler

* error: remove redundant redaction predicates (#349) by mikehostetler

* util: reuse validation and registry setup (#348) by mikehostetler

* observe: simplify span error completion (#360) by mikehostetler

* observe: share configuration precedence lookup (#351) by mikehostetler

* simplify persistence and runtime store access (#353) by mikehostetler

* topology: narrow startup task inputs (#356) by mikehostetler

* scheduler: simplify reconciliation and validation (#352) by mikehostetler

* plugin: share result checks and remove unused Bus field (#359) by mikehostetler

* agent_server: use one attachment monitor map (#355) by mikehostetler

* reuse authoring data in topology planning and encoding (#354) by mikehostetler

* agent: share common definition validation (#350) by mikehostetler

* complete V3 compatibility and maintenance cleanup by mikehostetler

* scheduler: supervise SchedEx jobs by mikehostetler

* agent: use Zoi for state schemas by mikehostetler

## Unreleased — V3 beta candidate

### Features

* split Plugin packages into Agent, Agent Server, Persistence, and Topology owner facets
* add stable Agent references and Ref-first instance operations
* add versioned durable records, tombstones, write-authority fencing, and runtime reconstruction
* add static Topology Plugin planning and semantic runtime observation

### Compatibility

* select Hex `jido_action 3.0.0-beta.11` and `jido_signal 3.0.0-beta.4`
* retain current V3 public APIs through the `3.0.x` line
* defer live code migration, live Topology replacement, and distributed control-plane claims
* beta.1 includes the optional Bedrock adapter without verified strict durability or MinIO snapshot recovery; real Bedrock tests are skipped pending upstream fixes
* beta.1 is verified on Elixir 1.20.3/OTP 29.0.5; its Elixir 1.18.5/OTP 27 test gate fails during example compilation

## [v2.3.3](https://github.com/agentjido/jido/compare/v2.3.2...v2.3.3) (2026-08-10)




### Bug Fixes:

* deps: update Mint for CVE-2026-59249 by mikehostetler

* instance-manager: fail closed on thaw errors (#316) by mikehostetler

* agent-server: serialize sync call drain races (#312) by mikehostetler

## [v2.3.2](https://github.com/agentjido/jido/compare/v2.3.1...v2.3.2) (2026-06-09)




### Bug Fixes:

* keep ETS storage tables supervised by mikehostetler

* remove ok dependency (#308) by mikehostetler

* harden storage and signal target handling by mikehostetler

### Refactoring:

* replace deep_merge dependency (#309) by mikehostetler

## [v2.3.1](https://github.com/agentjido/jido/compare/v2.3.0...v2.3.1) (2026-06-02)




### Bug Fixes:

* update jido_signal lock for OTP 29 by mikehostetler

* agent: simplify state validation branch by mikehostetler

* pod: resolve strategy module alias in Pod.__using__/1 by Jaden

## [v2.3.0](https://github.com/agentjido/jido/compare/v2.2.0...v2.3.0) (2026-05-22)




### Features:

* sensor: add tagged sensor lifecycle directives by mikehostetler

* observe: centralize telemetry emission by mikehostetler

* error: sanitize public error payloads by mikehostetler

* plugin: add phase callbacks with runtime context by mikehostetler

* agent: move identity modules under agent namespace (#277) by mikehostetler

* replace tzdata with time_zone_info to remove hackney dependency (#242) by dl-alexandre

### Bug Fixes:

* observability: quiet routed action logs (#264) by mikehostetler

* ensure Elixir 1.20 compatibility (#251) by mikehostetler

* expand plugin aliases in Pod macro before escaping (#239) by Jaden

### Refactoring:

* logging: localize lazy logger calls by mikehostetler

* fix ex_slop findings by Danila Poyarkov

## [v2.2.0](https://github.com/agentjido/jido/compare/v2.1.0...v2.2.0) (2026-03-29)




### Features:

* add partitioned multi-tenancy support (#218) by mikehostetler

* rebuild multi-tenancy around partitioned pods by mikehostetler

* reduce default log verbosity (#219) by dl-alexandre

* add first-class orphan lifecycle and adoption (#213) by mikehostetler

* add first-class orphan lifecycle and adoption (#212) by mikehostetler

* add first-class orphan lifecycle and adoption by mikehostetler

### Bug Fixes:

* remove invalid doctest-style doc examples (#227) by mikehostetler

* reject instance manager lifecycle opts in SpawnAgent (#222) by mikehostetler

* reject instance manager lifecycle opts in SpawnAgent by mikehostetler

* reduce default log verbosity (noisy logs) by dl-alexandre

* align action logging with instance config (#217) by mikehostetler

* observability: align action logging with instance config by mikehostetler

* observability: align action telemetry with log args by mikehostetler

* agent_server: always wrap parent-down reason as {:shutdown, _} by mikehostetler

* thread: handle missing thread in filter_by_kind (#211) by Julian Scheid

* thread: handle missing thread in filter_by_kind by Julian Scheid

* thread: tighten filter_by_kind guards by Julian Scheid

* agent_server: always wrap parent-down reason as {:shutdown, _} (#207) by Julian Scheid

* pass details as keyword to execution_error (#206) by Julian Scheid

* pass details as keyword to execution_error by Julian Scheid

* preserve execution error details compatibly by Julian Scheid

* agent: correct plugin_schedules typespec (#204) by CptnKirk

* restore git_ops changelog marker placement by mikehostetler

### Refactoring:

* formalize pod extraction seams (#233) by mikehostetler

* harden SpawnAgent directive validation by mikehostetler

* agent: pass jido instance via strategy context by mikehostetler

* harden runtime store ownership and stress adoption by mikehostetler

## [v2.1.0](https://github.com/agentjido/jido/compare/v2.0.0...v2.1.0) (2026-03-14)

### Features:

* scheduler: durable in-house cron scheduler for Jido 2.1 (#181) by mikehostetler

* scheduler: in-house cron engine with durable instance replay by mikehostetler

* plugin: support static subscriptions and fix documentation (#198) by Iulian Costan

* plugin: support static subscriptions and fix documentation by Iulian Costan

* storage: add Redis storage adapter (#184) by austin macciola

* storage: add Redis storage adapter by austin macciola

### Bug Fixes:

* ci: resolve lint guard and dialyzer issues by mikehostetler

* finalize durable scheduler hardening and dialyzer cleanup by mikehostetler

* scheduler: harden durable cron replay and callbacks by mikehostetler

* scheduler: restore cron replay invariants by mikehostetler

* misplaced end in example (#201) by Jan Pieper

* sensor: resolve via refs for subscription signals (#200) by mikehostetler

* storage: harden redis adapter and instance integration by austin macciola

* Improve typespec precision (#196) by Philip Munksgaard

* preserve plugin spec structs in agents (#188) by mikehostetler

* normalize StopChild shutdown reasons by mikehostetler

* align StopChild with SpawnAgent restart semantics by mikehostetler

* util: use Code.ensure_compiled to resolve action validation ordeâ¦ (#183) by caike

* util: use Code.ensure_compiled to resolve action validation ordering by caike

* error: make Jido.Error splode conversions reliable by Pascal Charbonneau

* observe: harden sync and async tracer span semantics (#178) by mikehostetler

* observe: harden tracer sync and async span semantics by mikehostetler

* observe: prevent cross-process scoped callback re-execution by mikehostetler

### Refactoring:

* scheduler: simplify runtime registration by mikehostetler

## 2.0.0 - 2026-02-22

### Changed
- Promote `2.0.0-rc.5` to stable `2.0.0`
- Require Elixir `~> 1.18`
- Bump ecosystem deps to stable ranges: `jido_action ~> 2.0`, `jido_signal ~> 2.0`

### Fixed
- Restore compile-time `signal_routes` behavior while preserving callback compatibility (#170)
- Prevent loopback `emit` from redispatching to the current agent in AgentServer (#171)

### Tooling
- Align Igniter setup/docs with the instance-scoped API

## 2.0.0-rc.5 - 2026-02-16

### Added
- Observability V2: per-instance debug & telemetry configuration (#129)
- Always-on `emit_event` helper for lifecycle observability (#141)
- Event contracts and lifecycle observability docs (#140)
- Directive struct included in agent_server telemetry metadata (#134, #142)
- `RunInstruction` directive and pure FSM cmd (#139)
- Prevent synchronous signal-call blocking in AgentServer (#150)
- Declarative schedules DSL for cron (#137)

### Changed
- **BREAKING**: Unify persistence on `Jido.Persist` and `Jido.Storage` (#156)
- Centralize defaults and validate observability config
- Harden InstanceManager registry and key semantics (#156)
- Share instruction tracking helpers in strategy layer (#166)
- Use shared templates in Igniter generator tasks (#165)
- Unify entry normalization across storage adapters (#164)
- Extract shared signal collector test helper (#167)

### Fixed
- Normalize timeout diagnostics in `await_all`/`await_any` (#168)
- Cancel timed-out completion waiters in AgentServer (#162)
- Preserve file read errors during append (#163)
- Return normalized errors for corrupt entry logs (#161)
- Avoid atom creation from persisted journal kinds (#160)
- Restore agent metadata export for discovery (#159)
- Return routing error struct for unknown signals (#155)
- Normalize refinement errors for Zoi validation in plugins
- Make ETS `append_thread` atomic and revision-safe (#150)
- Send `jido.agent.stop` when stopping child (#138)
- Normalize id in both constructor paths to guarantee UUID7 (#132)
- Fix silent cron tick failure (#137)
- Normalize util and storage-facing error contracts (#153)
- Offload runtime dispatch from sensor process (#152)

### Dependencies
- Bump `jido_action` and `jido_signal` to 2.0.0-rc.5

---

## 2.0.0-rc.4 - 2026-02-06

### Added
- Memory plugin: implement `Jido.Memory` as default plugin under `__memory__` key (#125)
- Identity plugin: add `Jido.Identity` as default agent plugin (#126)
- Plugin singleton flag in plugin config schema (#120)
- Plugin signal middleware improvements (#123)

### Changed
- Update `signal_routes` to accept context parameter (#121)

### Fixed
- Wire `on_restore/2` into generated `restore/2` callback (#122)

### Tests & Chores
- Add memory plugin and default plugins persistence examples (#127)
- Organize example tests into subdirectories (#124)
- Add `Jido.Plugin` to doctor ignore_modules for macro-generated defs
- Remove AI cruft and build artifacts

### Dependencies
- Bump `jido_action` and `jido_signal` to 2.0.0-rc.4

---

## 2.0.0-rc.3 - 2026-02-04

### Added
- `cmd/3` to support per-action timeout opts (#117)
- Unified persistence layer for agent checkpoints and thread journals (#110)
- Telemetry infrastructure with span tracking and metrics (#109)
- Debug helpers and improved timeout errors (#111)

### Changed
- **BREAKING**: Renamed `Jido.Skill` to `Jido.Plugin` (#115)

### Fixed
- Dialyzer/Credo: add :mix to PLT, remove unnecessary ignores (#118)

### Dependencies
- Bump `jido_action` and `jido_signal` to 2.0.0-rc.3
- Bump `ex_doc` from 0.40.0 to 0.40.1 (#112)

---

## 2.0.0-rc.2 - 2025-01-30

### Changed
- **Zoi Schema Migration**: Convert remaining structs to use Zoi schemas for consistent validation (#106)
- **Macro Decomposition**: Decompose large macros and improve code organization (#101)
- **Sensor Simplification**: Simplify `handle_event/2` to directive-only format (#108)

### Fixed
- Address code quality issues from codebase review (#107)
- Improve process lifecycle handling and test reliability (#100)

### Dependencies
- Bump `jido_action` and `jido_signal` to 2.0.0-rc.2

---

## 2.0.0 (Architecture Preview Notes) - 2025-12-31

### Added
- **Instance-Scoped Supervisors**: Jido now uses user-owned, instance-scoped supervisors instead of auto-started global singletons
- **Jido Supervisor Module**: New `Jido` module acts as a Supervisor managing per-instance Registry, TaskSupervisor, and AgentSupervisor
- **Agent Lifecycle API**: New functions `Jido.start_agent/3`, `Jido.stop_agent/2`, `Jido.whereis/2`, `Jido.list_agents/1`
- **Test Isolation**: New `JidoTest.Case` module for automatic test isolation with unique Jido instances
- **Per-Instance Scheduler**: Scheduler can now be scoped to a Jido instance
- **Multi-Agent Coordination**: New `Jido.await/3` and `Jido.await_child/4` for coordinating agent completion
- **Discovery Delegates**: Discovery functions accessible via main Jido module

### Breaking Changes
- **Explicit Supervision**: Users must now add `{Jido, name: MyApp.Jido}` to their supervision tree
- **Agent Start**: Use `Jido.start_agent(instance, agent, opts)` instead of `AgentServer.start/1`
- **Instance Option**: Pass `jido: MyApp.Jido` option when starting agents directly

### Changed
- Refactored from global singletons to instance-scoped architecture
- Agents now register in instance-specific Registry
- TaskSupervisor and AgentSupervisor are per-instance
- Updated all examples to use new 2.0 patterns

### Migration from 1.x
See the Migration section in README.md for upgrade instructions.

---

## Unreleased - 2025-08-29

### Added
- **Modular API Architecture**: Refactored monolithic `Jido.ex` module into specialized modules:
  - `Jido.Agent.Lifecycle` - Agent lifecycle management (start, stop, restart, clone operations)
  - `Jido.Agent.Interaction` - Agent communication (signals, instructions, requests)
  - `Jido.Agent.Utilities` - Helper functions (via/2, resolve_pid/1, generate_id/0, log_level/2)
- **Comprehensive Test Helpers**: New `JidoTest.Support` module with common test utilities:
  - Registry management helpers (`start_registry!/0`)
  - Agent lifecycle helpers (`start_basic_agent!/1`, automatic cleanup)
  - Signal and state assertion helpers
  - Consistent test patterns across all modules
- **Table-Driven Test Coverage**: Implemented data-driven delegation tests for maintainable 100% API coverage
- **Performance-Optimized Test Suite**: Consolidated and streamlined tests with `@tag :slow` for optional performance tests

### Breaking Changes
- **None**: All public API functions remain fully backward compatible through delegation in main `Jido` module

### Changed
- **Improved Test Performance**: ~40% reduction in test execution time through:
  - Elimination of redundant test cases
  - Reduced UUID generation from thousands to ~110 total
  - Parameterized test scenarios instead of copy-paste patterns
  - Common setup helpers reducing boilerplate
- **Enhanced Test Maintainability**: 
  - Centralized test helpers eliminate code duplication
  - Table-driven tests make adding new API methods trivial
  - Consistent patterns across all test files
- **Better Resource Management**: Automatic test cleanup prevents resource leaks and test isolation issues

### Fixed
- **Test Suite Optimization**: Removed redundant tests while maintaining high coverage (68.4% overall, >80% for key modules)
- **Code Quality**: Addressed Credo warnings in test files (replaced `length/1` with `Enum.empty?/1`)

---

## Previous - 2025-08-25

### Added
- **Automatic Action Registration**: Skills can now declare required actions in their configuration using the `actions` field, which are automatically registered when the skill is mounted
- **Module Path Refactoring**: Moved action modules from `Jido.Actions.*` to `Jido.Tools.*` namespace for better alignment with `jido_action` library
- **Default Skills**: Agent server now uses default skills (`Jido.Skills.Basic` and `Jido.Skills.StateManager`) instead of hardcoded actions

### Breaking Changes
- **Action module paths**: All action modules moved from `Jido.Actions.*` to `Jido.Tools.*` to align with the `jido_action` library
- **Runner system removed**: The separate `Jido.Runner.Simple` and `Jido.Runner.Chain` modules have been deprecated. Agents now use built-in execution logic that processes one instruction at a time (equivalent to the former Simple Runner behavior)

### Changed
- **Skill configuration**: Skills can now declare required actions using the `actions` field for automatic registration
- **Agent options**: Both `actions:` and `skills:` options are supported, with skills providing the preferred declarative approach

### Fixed
- Task update action now only updates provided fields instead of overwriting with nil values
- State manager update action now uses `:update` operation instead of `:set` for proper semantic behavior
- Improved error handling for action registration failures

## 1.1.0-rc.1 - 2025-02-18

- Address open Credo Errors
- Add documentation
- Clean up README in prep for 1.1 release

## 1.1.0-rc - 2025-02-08

- Stateful Agents
