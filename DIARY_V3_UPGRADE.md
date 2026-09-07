# Jido v3 Upgrade Diary

Status: Working document  
Branch: `v3-spike`  
Initial snapshot date: 2026-08-28  
Current checkpoint date: 2026-09-07  
v2 baseline: `548b2a34` (`main`)  
Initial spike head: `f5c37675`  
Latest code checkpoint: `aaba18fe`

## Purpose

This diary records why the Jido v3 spike changed. It is source material for a
future announcement, blog post, and upgrade guide.

This is a reconstruction from the Git commit stack. It is not a claim that each
spike decision is final. An entry states its status when this file was written.
Future entries must keep that distinction clear.

The August spike has 19 commits after the v2 baseline. The last 10 commits form one
Agent definition and DSL experiment. This diary treats them as one change. It
does not change or combine the Git history.

The September entries continue the record after the work moved into Core. In
those entries, **Reason** records the selected contract or evidence from the
source, guides, tests, and user decisions. **Lesson** is the diary's
interpretation of what the work means. A later entry can supersede an earlier
proposal without rewriting that earlier proposal as if it was final.

## Guiding principle — Design for agent-written code

Jido v3 assumes that coding agents will write and change much of the code that
uses its APIs. Small helpers that only save a person a few keystrokes now have
less value. Each extra input form still adds normalization code, tests,
documentation, error cases, and maintenance work.

For example, a tuple that contains a Jido Action can normalize to an
Instruction. This is convenient shorthand, but it does not add domain meaning.
A coding agent can create the explicit Instruction directly. Supporting both
forms makes the runtime and its public contract harder to understand.

Prefer one explicit, canonical form when a helper only shortens syntax. Keep a
helper when it expresses domain intent, prevents a real error, or makes code
materially easier to understand. Optimize the API for clear meaning and local
reasoning, not for the fewest typed characters.

## 2026-08-26 — Use Zoi for Action schemas

Status: Retain the direction. Review exact public syntax before release.  
Commit: `af3014ed` — `refactor!: convert Action schemas to Zoi`

### Problem

Jido Actions still used the old keyword-list schema form. `jido_action` v3 uses
Zoi. Two schema systems made Action authoring and validation harder to explain.
They also required compatibility code at package boundaries.

### Change

The built-in control, lifecycle, scheduling, status, identity, and Pod Actions
now use Zoi schemas. Test Actions use the same form.

For example, a field with a default changed from a NimbleOptions-style entry to
a Zoi field:

```elixir
schema:
  Zoi.object(%{
    reason: Zoi.any() |> Zoi.default(:cancelled)
  })
```

### Reason

Jido needs one schema language across the core packages. Zoi gives Actions a
typed data model and supports composition with the v3 Action and Flow APIs.

### Effect

Action authors must move old keyword schemas to Zoi. Action execution did not
change because of this commit. An Action can still do I/O.

### Lesson

A common schema system removes adapter code. It does not define the Actor
effect boundary. Schema purity and Action side effects are different concerns.

## 2026-08-26 — Move the Agent runtime to `jido_action` v3

Status: Migration is active. Some new runtime concepts remain under review.  
Commit: `2d1908b5` — `feat!: migrate Agent runtime to jido_action v3`

### Problem

The Agent runtime depended on v2 Action metadata, error types, Instructions,
and execution calls. This made Jido own compatibility code that belonged at the
Action package boundary. It also blocked `Jido.Flow` from becoming a normal
executable target.

### Change

The runtime moved to the v3 `Jido.Executable`, `Jido.Instruction`, and
`Jido.Exec` contracts.

The spike added `Jido.Agent.Command` as the Agent-facing invocation value. It
can normalize an Action, a Flow, an Instruction, or the supported tuple forms.
It keeps Agent execution policy separate from Instruction metadata.

The Direct strategy now converts each Command at the execution boundary and
calls `Jido.Exec.run/4`. Action discovery now uses `Jido.Executable`. The local
Jido error compatibility module was removed in favor of the package contract.
`RunInstruction` was changed to carry a Command.

### Reason

The Action package must own executable resolution and execution. Jido core must
only add the Actor or Agent semantics that surround that execution. A Flow must
be usable through the same executable seam as an Action.

### Effect

This was a broad migration. It changed runtime code and more than 80 test and
example files. It kept the current `cmd/2` and Strategy model working while the
underlying package API changed.

### Open concern

`Jido.Agent.Command`, `RunInstruction`, and the Direct strategy reflect the
current v2 Agent architecture. The later Actor design can remove most Strategy
machinery. If that occurs, Command must be kept only if it remains a useful
public boundary. It must not survive only to support a retired Strategy layer.

## 2026-08-26 — Move Signal handling to `jido_signal` v3

Status: Retain the package direction.  
Commit: `65489a6e` — `feat!: migrate Signal APIs to v3`

### Problem

Jido core used Signal extension registration, extension-backed tracing, optional
Signal sources, NimbleOptions-style Signal schemas, and a Journal API that no
longer exists in `jido_signal` v3.

### Change

Built-in runtime Signals now have an explicit default source and a Zoi schema.
Trace values now use Signal context attributes. Jido no longer starts a Signal
extension registry. The Journal-backed Thread store adapter was removed from
core.

### Reason

Core must use the Signal package contract. It must not reproduce APIs that the
Signal package removed. Signal origin and context must be explicit data.

### Effect

Custom code that used the removed extension or Journal APIs needs a new
integration. The in-memory Thread store remains. Trace correlation remains,
but its storage format changed to context attributes.

### Lesson

The package seam became smaller. Jido core now owns less global Signal setup.
This supports the later Actor goal: messages enter one mailbox with explicit
identity and context.

## 2026-08-26 — Update the public v3 contract documentation

Status: Historical checkpoint. The final v3 guide will need another rewrite.  
Commit: `b5f1c321` — `docs: document v3 core contracts`

### Problem

The code used new Action and Signal contracts, but the guides still taught v2
forms. This made the spike hard to test as a developer experience.

### Change

The README and 23 guides were updated for the new schemas, commands, errors,
signals, directives, runtime behavior, and package APIs.

### Reason

Documentation is part of the public API test. If a design cannot be explained
in short examples, the design is not yet simple enough.

### Effect

The commit made the first migration phase reviewable. It is not the final v3
documentation. Later Actor and Agent naming decisions can supersede it.

## 2026-08-26 — Remove Jido-owned schema adapters

Status: Retain the simplification.  
Commit: `c7475fbd` — `refactor(agent): use Zoi for state schemas`

### Problem

The first v3 migration added `Jido.Schema` and continued to use the existing
`Jido.Agent.Schema` wrapper. These modules copied schema checks, default
extraction, and merge behavior that the Action and Zoi layers could provide
directly.

### Change

The spike removed both wrapper modules and their tests. Agent state schemas are
now field-based Zoi map schemas. State validation uses Zoi directly. Strict mode
strips unknown keys. Normal mode preserves them. Plugin state schemas use the
same path. Static-schema checks use `Jido.Action`.

### Reason

Jido must not add a second vocabulary around Zoi when direct use is clear. The
package that defines static executable schemas must own the shared safety
check.

### Effect

The change removed more than 1,000 lines. It made the schema rule narrower and
easier to state: Agent state is a Zoi object schema, or it has no schema.

### Lesson

The spike first added a bridge and then removed it. This is a useful v3 rule:
do not make a Jido abstraction only to rename an ecosystem abstraction.

## 2026-08-27 — Consume published v3 beta packages

Status: Temporary dependency checkpoint.  
Commit: `d7136f4f` — `chore(deps): update Jido v3 beta dependencies`

### Problem

The spike used `jido_action` beta.1 and a fixed Git revision of `jido_signal`.
This made the package set harder to reproduce and did not test the published
v3 integration surface.

### Change

The dependencies moved to the published `3.0.0-beta.2` releases of
`jido_action` and `jido_signal`.

### Reason

Jido v3 must integrate through released package contracts. A private Git pin
can hide missing versioned APIs.

### Effect

The core spike now tests one coherent beta generation. These beta versions are
not a final release promise.

## 2026-08-27 — Remove the Igniter install and generator surface

Status: Removed on the spike. Confirm before the final release.  
Commit: `d8c80d61` — `refactor(install)!: remove Igniter integration`

### Problem

Jido maintained an optional Igniter dependency, an installer, three generators,
templates, tests, and install guidance. These tools encoded v2 concepts while
the v3 authoring and runtime model was still changing.

### Change

The spike removed the Igniter integration and the `jido.install`,
`jido.gen.agent`, `jido.gen.plugin`, and `jido.gen.sensor` Mix tasks.

### Reason

Generators increase the public surface and repeat design choices in templates.
They are costly while the core model is unstable. The first v3 release should
prefer a small, direct API.

### Effect

Users cannot use the removed Mix tasks on this spike. A future package can add
generation after the v3 concepts and names are stable.

### Lesson

Developer experience does not always improve when Jido adds a helper. A small
manual example can be better than generated code that teaches the wrong model.

## 2026-08-27 — Remove retired repository workflow files

Status: Complete repository cleanup.  
Commit: `891764cf` — `chore(repo): remove obsolete internal workflow files`

### Problem

The repository contained old Beadwork instructions, local agent skills, a
retired specification workspace, and an old helper script. These files no
longer described the active design process.

### Change

The obsolete internal files were removed.

### Reason

Old process documents can appear authoritative and conflict with current ADRs
and code. The repository must have one active design record.

### Effect

There was no product runtime change. This diary and the v3 ADR set must carry
the design story instead of the retired workspace.

## 2026-08-27 — Put scheduled jobs under OTP supervision

Status: Retain the OTP direction. Review the SchedEx dependency before release.  
Commit: `65af880b` — `refactor(scheduler): supervise SchedEx jobs`

### Problem

Jido had its own cron parser, time-zone calculation, timer retry loop, callback
worker tracking, and forced process shutdown logic. `AgentServer` kept live job
PIDs and had too much lifecycle code. This duplicated scheduling work and made
ownership hard to see.

### Change

SchedEx now calculates and runs schedules. Each Jido instance has a scheduler
supervisor. Each registered job runs under that supervisor. A small Jido job
process monitors the owning Agent process and stops when its owner stops.

`AgentServer` stores stable job names instead of raw job PIDs. Durable schedule
definitions remain separate from live jobs. The old cron runtime specification,
custom scheduling engine, and related tests were removed.

### Reason

OTP supervision must own process lifecycle. The Agent runtime must define job
ownership, but it does not need to implement a cron engine.

### Effect

The change removed about 1,000 net lines. Agent shutdown now has a clear path to
scheduled-job shutdown. Restart and failure behavior is visible in the
supervision tree.

### Open concern

The spike pins SchedEx to a Git revision. The final release needs a stable
dependency decision and focused tests for owner death, restart, cancellation,
and durable schedule restoration.

## 2026-08-27 — Test a canonical Agent definition and DSL

Status: Provisional experiment. Do not treat this API or name as final.  
Commits: `c7524003` through `f5c37675`

This is one design change made through 10 implementation commits:

- `c7524003` — add the canonical Agent definition
- `80454153` — separate compile and instantiate boundaries
- `aff77e5c` — add a Builder
- `0cfb832d` — add a trusted Registry
- `42a34ec7` — add a versioned Codec
- `c8d88ce1` — add a Spark authoring DSL
- `c73a45c8` — add typed extensions
- `eafa7798` — migrate v2 authoring paths
- `8b18c640` — simplify the internals
- `f5c37675` — resolve review findings

### Problem

The v2 `%Jido.Agent{}` mixed several boundaries:

- author definition data;
- live runtime identity and state;
- compiled plugin, route, and schema data;
- module DSL output;
- storage and reconstruction concerns.

Direct data, module authoring, dynamic construction, and stored definitions did
not have one canonical result. Anonymous functions and closures could also
enter schemas or routes and make definitions unsafe to store or compare.

### Experiment

The batch tested one canonical, inert `%Jido.Agent{}` definition. It separated
that value from compiled data and runtime instantiation.

It added four authoring boundaries that produce the same value:

1. direct Elixir data;
2. a pipeline Builder;
3. a Spark module DSL;
4. a versioned neutral document through a Codec.

The experiment also added:

- explicit Plugin, Schedule, and Extension declarations;
- a trusted Registry for modules, schemas, atoms, functions, and extension
  values;
- a semantic identity that excludes runtime and host-derived data;
- source maps for DSL errors;
- typed Spark extensions for package overlays;
- compatibility aliases for selected v2 authoring forms;
- rejection of anonymous functions and closures in portable schema data;
- a rule that JSON text cannot create a module or atom.

The main parity test proves that direct data, Builder output, Spark DSL output,
and a Codec round trip can produce one equal canonical value.

### Reason

An Agent definition must be data before it becomes a running process. Authoring
syntax must not change the meaning of that data. Storage must cross a trusted,
versioned boundary. Compile-time convenience must not leak into canonical
identity.

### What this experiment proved

The following ideas remain useful even if the current DSL is replaced:

- There must be one canonical definition value.
- Definition, compilation, instantiation, and process start are different
  boundaries.
- All authoring forms must have semantic parity.
- Portable schemas cannot contain closures.
- Stored identifiers must resolve through a trusted host Registry.
- Codec data and runtime checkpoint data are different formats.
- Host defaults and source locations must not change semantic identity.

### Why this is not final

The batch is large. It can make a new developer learn Builder, Compiler,
Compiled, Registry, Codec, Spark DSL, extensions, and compatibility forms before
they understand the runtime.

More important, the current architecture review questions the name and owner of
the definition. Core Jido can rename its OTP abstraction from `Jido.Agent` to
`Jido.Actor`. The `jido_ai` package can then own `Jido.Agent` as the common
AI-agent abstraction. If this direction is accepted, much of this experiment
must move from `%Jido.Agent{}` to `%Jido.Actor{}` or be removed.

The experiment also migrated away from selectable strategies, but the current
code still contains Strategy-era runtime seams. The definition DSL must not
make those seams permanent.

### Review rule

Review this batch as one hypothesis:

> One canonical definition can support direct data, programmatic building,
> module DSL authoring, and safe storage without changing its meaning.

Do not review each commit as a separate product commitment. Do not preserve a
type or module only because this experiment already implemented it.

## 2026-09-05 — Build the V3 replacement in Jido Core

Status: Implemented on `v3-spike`. Release validation is not complete.  
Key commits: `9bc060a7` through `ae05ac44`

### Problem

Jido Core needed a reviewable path from the V2 baseline to the V3 runtime. A
large replacement in one change would make it difficult to separate runtime,
persistence, examples, and compatibility results.

### Change

Core received the work through an ordered series of commits. The series first
replaced the runtime, then added persistence and remote lifecycle checks. It
then added the example groups, Topology, application scenarios, and
current-main maintenance work. The implementation sequence reached M12.

This sequence did not implement the later redesign proposals in `docs/design`.
The Ref facade, a new Plugin pipeline, and a replacement persistence design
remain proposals.

### Reason

The migration contract required Core to prove its own build, tests, examples,
and application behavior. It also required each old Core file and test to have
an explicit disposition.

### Effect

The V3 runtime, authoring APIs, examples, and application scenarios now form one
development line in Jido Core on `v3-spike`. Completing the implementation
sequence does not mean that the beta release gate is complete.

### Lesson

A large rewrite is easier to verify when each stage has a clear scope and its
own proof. Passing one stage does not prove the later integration or release
gate.

## 2026-09-05 — Keep Agent as the Core name

Status: Implemented. This supersedes the proposed Actor and AI-Agent split.  
Key commit: `9bc060a7` — `refactor(agent)!: replace the V2 runtime with the V3 command contract`

### Problem

The August review proposed that Core own `Jido.Actor` and that `jido_ai` own
`Jido.Agent`. That proposal helped separate the OTP runtime concept from the AI
concept, but it was not the final Core contract.

### Change

The implemented public names are `Jido.Agent` and `Jido.AgentServer`.

`Jido.Agent` is a complete immutable domain value. A Signal selects one Action
or Flow. Direct execution returns one of these results:

```elixir
{:ok, candidate, directives}
{:error, reason}
```

The candidate contains the complete next Agent state. `Jido.AgentServer` owns
live execution. It admits Signals, serializes Turns, commits one validated
candidate, and starts the effects that follow that commit.

Actions and Flows can perform I/O during a Turn. A failed Turn preserves the
last committed Agent state. It cannot undo external I/O that already occurred.

### Reason

The implemented source and the Core migration guide explicitly keep the Agent
and AgentServer names. They define this work as a V3 API replacement, not as
the Actor rename proposed in the earlier design study.

### Effect

Core users have one main stateful abstraction named Agent. Application code
sends Signals, returns complete candidate state, and uses Directives when work
must occur after commit. The `jido_ai` package does not yet own a new public
`Jido.Agent` type.

### Lesson

The useful part of the Actor study was the ownership boundary, not the name.
The final name can stay `Agent` while the design still separates domain state,
serialized execution, and runtime resources.

## 2026-09-05 — Retain one canonical Agent and explicit ownership

Status: Implemented in the V3 design.

### Problem

The earlier runtime mixed definition data, live process data, Plugin state,
child process references, and persistence concerns. Multiple representations
made it difficult to know which value was authoritative.

### Change

The implemented design keeps these boundaries:

- Static Zoi schemas define Agent, Plugin, Action, Flow, and public data
  contracts. Core does not restore NimbleOptions or multi-schema support.
- The module DSL, Builder, and Codec produce the same canonical Agent
  definition.
- Each Plugin has explicit callbacks, configuration, and one owned state key.
- Required Plugin runtimes and child Agents are owned processes. Their PIDs and
  other runtime references do not enter portable Agent state.
- Topology composes static Agent systems without changing the canonical Agent
  value.
- Checkpoints contain portable state and identity data. Restore checks the
  saved module, identity, schema, and recursive portability rules.

### Reason

The implemented contracts require one complete Agent value at each state
boundary. They also require OTP resources to stay under explicit supervisors
and outside portable domain state.

### Effect

Application Actions and Flows return complete domain state. Plugins change only
their declared state or Directives. Runtime code owns tasks, timers, child
processes, and resource clients. Persistence can rebuild portable state, but it
does not claim that an external effect can be rolled back or that every runtime
resource can be serialized.

### Lesson

The stable idea is not a specific DSL form. The stable idea is one canonical
value with clear owners around it. DSL, Builder, Codec, live execution, and
storage must not create competing meanings for the same Agent.

## 2026-09-05 — Replace V2 instead of running two contracts

Status: Implemented in the V3 candidate. Downstream ports remain.

### Problem

Keeping the V2 and V3 contracts active together would preserve two command
models, two state update models, and several retired runtime layers. That would
move compatibility work into every new feature.

### Change

The V3 candidate removes incompatible V2 surfaces instead of maintaining them
beside the new runtime. The main changes are:

- Signals select Actions or Flows. `cmd` no longer accepts the old Instruction,
  Action, and tuple shorthand set.
- Complete candidate state replaces state patches and StateOps.
- The fixed Turn model and V3 Plugin callbacks replace Strategy, FSM Strategy,
  and before or after command hooks.
- Typed Plugin Directives replace `DirectiveExec` and the old directive handler.
- Instance-scoped lifecycle, explicit bounded workers, owned children, and
  static Topology replace the public InstanceManager, WorkerPool, and mutable
  Pod graph APIs.
- V3 compare-and-swap records replace the old Storage checkpoint and integrated
  Thread storage APIs. Old Actor and V2 envelopes are rejected. There is no
  automatic data converter.
- Sensor, Discovery, integrated Memory, and identity-profile frameworks are not
  part of this Core candidate.

The prior simplifications remain part of this decision. Zoi is the schema
language. Core does not add a schema adapter. Scheduling uses SchedEx under OTP
supervision. After upstream fixed its dependency issue, commit `10ebacd4`
replaced the Git pin with the fixed SchedEx `1.2.1` release.

### Reason

The migration guide defines V3 as a major API change without source
compatibility or automatic storage conversion. This keeps one active contract
inside Core.

### Effect

Applications must port commands, state transitions, Plugins, lifecycle calls,
and stored data. `jido_ai` still uses removed Strategy and Server State
contracts. `jido_browser` still uses the old Plugin contract. Both packages need
separate ports. This Core work did not port them.

### Lesson

A clean major version can remove compatibility cost, but it moves work to the
upgrade boundary. The upgrade guide and explicit data conversion rules are part
of the product, not cleanup after the product.

## 2026-09-05 — Use examples as application acceptance tests

Status: Implemented and passing in the recorded Core run.

### Problem

Unit tests alone could not prove that complete applications worked across the
Core integration boundaries. They also could not prove process ownership,
recovery, cancellation, and cleanup as one system.

### Change

Core now contains 52 catalog fixtures in these groups:

- Basic
- Workflow
- LLM
- Runtime
- Multi-agent
- Factory
- Topology

It also contains ten application scenarios. The tests use real Agent processes
and cover ownership, persistence uncertainty, recovery, remote calls,
cancellation, and cleanup. Deterministic model adapters and local HTTP and SSE
servers test LLM and streaming paths without paid provider calls.

### Reason

The migration acceptance contract required every fixture and application
scenario to have a nonempty Core test selection. Core had to run the complete
behavior itself.

### Effect

Examples now check complete application behavior, not only documentation
syntax. They found lifecycle and concurrency faults that smaller tests did not
show. These checks do not prove model quality, paid provider behavior,
multi-host fault tolerance, or general production readiness.

### Lesson

An example is stronger when it is also an executable claim. A large rewrite
needs examples that cross package, process, persistence, and cleanup boundaries.

## 2026-09-05 — Preserve startup errors across process exit

Status: Fixed and covered by controlled concurrency tests.  
Commit: `855a4c86` — `fix: preserve Agent startup errors and apply Flow copy fix`

### Problem

An Agent Server could stop during Plugin bootstrap before its caller began
waiting for readiness. The process exit could then hide the useful Plugin
bootstrap error.

### Change

The supervised startup paths now create a temporary OTP reply alias before they
start the child. The Server sends readiness or failure to that alias. The
caller removes the alias after the wait.

Two controlled tests suspend the startup caller. They then make Plugin startup
fail and let the Server exit before the caller resumes. Both tests failed before
the fix and passed after it.

### Reason

The public startup result must describe the bootstrap failure even when OTP
process exit wins the scheduling race.

### Effect

Callers receive the specific bootstrap error instead of a generic process-exit
result. The alias is private runtime state. It does not change Agent state,
checkpoint data, the Plugin contract, or the public PID API.

### Lesson

In concurrent startup code, the reply path must exist before the child can
finish. A deterministic race test needs an explicit barrier. Repeated sleeps do
not prove lifecycle ordering.

## 2026-09-05 — Consume the upstream Flow state-copy repair

Status: Fixed upstream and pinned in Core until a Hex release contains it.  
Upstream commit: `83fb5f18b812b973325ee4d2c418d6cc28ebcd52`

### Problem

The example suite appeared to stall. The exact command was:

```sh
mix test test/examples --include integration --include example --include flaky --seed 0
```

It did pass all 238 tests, but it took 103.9 seconds on this machine. Profiling
showed that Flow closures retained accumulated compiler and execution state.
Moving that value between processes copied far more data than the active Flow
needed.

### Change

The repair was made in upstream `jido_action`. Core pins the exact upstream
commit until a Hex release includes it. The dependency uses Runic
`0.1.0-alpha.10`.

In the measured case, the copied Flow execution value changed from
377,111,049 machine words to 208,173 words. The smaller value was 1,665,384
bytes on this machine.

With the fixed dependency, the same example command passed all 238 tests in
20.5 seconds on this machine.

### Reason

The fault belonged in the package that owns Flow construction and execution.
Core consumed that upstream repair instead of keeping a private edited copy
under `deps`.

### Effect

The example suite became fast enough to use during normal Core development.
The exact Git pin is temporary and must return to a released package after the
repair reaches Hex.

### Lesson

The reported sizes and times describe one machine and one test selection. They
are not general benchmarks. The useful result is the failure shape: a closure
can retain an entire evolving value and make process messages unexpectedly
large.

## 2026-09-05 — Make asynchronous example ordering explicit

Status: Test corrected without a skip or timeout increase.  
Commit: `855a4c86` — `fix: preserve Agent startup errors and apply Flow copy fix`

### Problem

Faster Flow execution exposed an ordering assumption in the Flow Factory test.
Review workers could begin before the mission committed its asynchronous
progress update. The test read the integration artifact too early.

### Change

The test now waits until the integration artifact appears. It then keeps the
original exact equality assertion. The change did not add a skip or increase a
timeout.

All 14 Flow Factory tests then passed. The final full command reported 1,042
passing tests and the one approved exclusion in 64.1 seconds. Format and
compile checks also passed. This result used the fixed `jido_action` dependency
and the final test change.

### Reason

Worker readiness and the mission's later progress commit are different events.
The assertion must wait for the event whose state it reads.

### Effect

The test now states the real asynchronous contract. It still checks the exact
artifact value after the commit becomes visible.

### Lesson

Better performance can expose hidden ordering assumptions. A test must wait for
the relevant state transition, not for a nearby event that usually happens
first.

## 2026-09-05 — Preserve the limits of the evidence

Status: Migration paused before the full release gate.

### Problem

A final green run can hide the difference between one successful checkpoint and
a completed release campaign. Earlier repeated runs also found intermittent
Factory worker-exit and streaming terminal-cancellation failures.

### Change

The current record keeps these limits explicit:

- DIST-03 remains excluded. The test is `one logical identity has at most one
  live cluster owner` in
  `test/jido/agent/distributed_authority_test.exs`. Cluster-exclusive ownership
  is not supported.
- The intermittent Factory worker-exit and terminal-cancellation failures have
  diagnostics, but their causes are not established. Later runs passed.
- The Flow copy repair did not prove the cause of either intermittent failure.
- The final multi-seed campaign, corrected 30-minute recovery run, and beta QA
  were not completed.
- One earlier 30-minute run passed on earlier code. A later run was stopped at
  the user's request.
- No beta release was published.

### Reason

The acceptance record treats an exclusion as an exclusion, not a pass. It also
requires final checks to run against the final source before their results can
support a release decision.

### Effect

The current full-suite result is useful development evidence. It is not a beta
release statement. Work can continue in Core without erasing the remaining
distributed-ownership and burn-in work.

### Lesson

Report what a test run proves and what it does not prove. Do not assign one fix
as the cause of a different intermittent failure without evidence.

## 2026-09-05 — Keep temporary migration records out of Core

Status: Complete repository and document cleanup.  
Commit: `d83710d2` — `chore: remove migration and review records from core`

### Problem

The large migration evidence tree was useful during the implementation work.
Keeping it as an active product surface would make temporary records look like
maintained Core documentation.

### Change

The user chose to remove `docs/migration` and `docs/reviews` from the active
Core tree. Core now ignores those working-record paths. Obsolete migration
scripts were removed, and retained guides were updated. Earlier Git commits
still contain the committed records. A local archive outside Core keeps the
complete working records.

### Reason

The selected repository policy keeps implementation and maintained guides in
Core. It keeps migration evidence outside the active source tree. This diary
remains the continuing record of major decisions and source material for future
writing.

### Effect

The active Core tree is smaller. The detailed evidence remains recoverable. The
diary can now develop with the product without restoring the temporary
migration workspace.

### Lesson

An archive can preserve evidence without making it part of the maintained
product. A diary is useful because it records the development of the design,
including decisions that were later reversed.

## Historical checkpoint — 2026-09-05

As of 2026-09-05, the work is in Jido Core on `v3-spike` at
`d83710d2c9559d9623353e81fd2561ce3b4571e6`. The branch is pushed to
`https://github.com/agentjido/jido/tree/v3-spike`.

The implemented directions are:

- Core keeps the public names `Jido.Agent` and `Jido.AgentServer`. The earlier
  Actor and AI-Agent split remains a historical proposal.
- A Signal selects one Action or Flow. Direct execution produces a complete
  candidate Agent and Directives. AgentServer owns serial execution and commit.
- Static Zoi schemas, the DSL, Builder, Codec, Plugin ownership, owned children,
  Topology, and portable checkpoints are part of the implemented design.
- V2 compatibility surfaces were removed instead of running two contracts.
- SchedEx `1.2.1` provides the upstream scheduling base under OTP supervision.
- Core temporarily pins the upstream `jido_action` Flow state-copy repair until
  it is in a Hex release.
- The 52 examples and ten application scenarios are executable Core checks.
- Explicit canonical values remain preferable to shorthand forms that exist
  only for typing convenience.

The latest recorded full run passed 1,042 tests with one approved DIST-03
exclusion in 64.1 seconds. Format and compile checks passed. This is development
evidence, not a beta release result.

The remaining limits are:

- Cluster-exclusive Agent ownership is not implemented.
- Two intermittent test failures have diagnostics but no established cause.
- The final multi-seed campaign, corrected 30-minute recovery run, and beta QA
  are incomplete.
- `jido_ai` and `jido_browser` still need separate V3 ports.
- The proposals under `docs/design` are not the implemented migration contract.
- No beta release has been published.

## 2026-09-07 — Commit the alpha for evaluation

Status: Alpha. Beta QA is incomplete.

### Change

- `5c8f9857` adds static Agent authoring extensions and tests.
- `2902f3f9` keeps Plugin lookup responsive during restart readiness. Tests
  cover committed state reads, owner shutdown, and readiness task failure.
- `aaba18fe` preserves structured errors from Plugin state schema callbacks.
- The README now identifies this branch as an alpha. The testing guide states
  that the full suite includes unmet research assertions.

### Evidence

Format, compilation with warnings as errors, strict warning-level Credo,
Dialyzer, documentation with warnings as errors, and Hex package build passed
on Elixir 1.20.3 / OTP 29.0.5.

A fresh production consumer used the unpacked Hex artifact and resolved its
own dependencies. It compiled and ran an Agent command on Elixir 1.18.5 /
OTP 27.3.4.12. ReqLLM was absent from that production runtime.

The complete suite on Elixir 1.18.5 / OTP 27.3.4.12 finished in 88.5 seconds:
1,280 tests, 11 failures, and the one approved exclusion. All failures match
the documented research acceptance gaps. This is a failed full-suite result.

The complete coverage run on Elixir 1.20.3 / OTP 29.0.5 finished in 601.9
seconds with the same 11 research failures and one approved exclusion. Core
coverage was 93.9%, above the required 90% and the 93% maintenance target.
Coverage does not change the failed test result.

### Open concerns

The package still declares version `2.3.3`. A V3 beta version and generated
release notes are required before publication. The dependencies now use Hex
releases, including `jido_action ~> 3.0.0-beta.7` and
`jido_signal ~> 3.0.0-beta.4`; the earlier temporary Git pin is gone.

The research acceptance record contains 11 unmet assertions across nine
proposed features. Their scope must be resolved before claiming a clean beta
release gate. Keep the assertions intact. Cluster-exclusive ownership also
remains unsupported. Repeated test seeds and recovery and scale checks remain
part of the release work. This checkpoint does not publish a package.

## Entry format for future changes

Add new entries in commit order. Use these fields:

```markdown
## YYYY-MM-DD — Short change name

Status: Proposed, provisional, retained, superseded, or removed.  
Commit: `12345678` — `type(scope): subject`

### Problem

State the user or maintenance problem.

### Change

State what changed.

### Reason

State why Jido owns this decision.

### Effect

State the developer and runtime effect.

### Lesson or open concern

State what the work proved and what remains uncertain.
```
