# Jido code-first examples

These examples pressure-test the current Jido API before the v3 design changes
the implementation.

The main catalog has 52 feature fixtures. The first five groups have 254 passing tests. Basic has five
source fixtures and five matching fixture test files. Six additional tests
compare authoring formats, for 22 SDK integration tests. See the
[Basic result report](../../docs/examples/basic-results.md) and the
[historical catalog results](../../docs/examples/implementation-results.md).
The main Multi-agent sequence starts real child Agents, including children on
another Erlang node.

Each example keeps its implementation and adapters in its source folder.
Matching test folders use the same numbered category and example ID. Core
acceptance tests stay under `test/jido`. The order is Basic, Workflow, LLM,
Runtime, Multi-agent, Factory, Topology, then the unresolved `99_research` queue. For example, the
first source folder is `01_basic/01_01_minimal_agent/`. Doc profile filenames use the same ID.
See the [catalog rules](../../docs/examples/README.md#catalog-rules).

Basic shares the
recording Plugin in `01_basic/01_04_directive_agent/effects.ex`; test setup stays in
`test/support/basic_sdk_case.ex`.

Run the complete opt-in suite from the project root:

```shell
mix test --only example
```

The short command is:

```shell
mix examples
```

The normal `mix test` command excludes these examples. Run one example with
its direct test path and the opt-in tag:

```shell
mix test --include integration test/examples/01_basic
```

## Startup and command APIs

Use the Jido instance API for startup:

```elixir
{:ok, server} = MyApp.Jido.start_agent(Jido.Examples.MinimalAgent, id: "counter-1")
{:ok, server} = Jido.start_agent(jido, Jido.Examples.MinimalAgent)
```

An omitted ID is generated. A supplied ID must be a nonempty string. Startup
options must be a keyword list. The Server links to the instance supervisor,
and caller exit does not stop it. A duplicate live ID returns an error without
replacing the existing Agent. `Server.start_link/1` provides caller-link
ownership when required.

The examples no longer repeat startup wrappers. The shared test runner uses
`Jido.start_agent/3`. Special operations such as required restoration keep their
own functions. All Agent declarations use Spark `agent` and `routes` blocks.
Nested `define` declarations generate named command helpers and Signal
constructors. Call them directly; do not add a `signal` alias around a generated
constructor. Use a domain verb such as `fetch_pair`, `answer`, or
`create_worker`. The `run/2` callback belongs to Actions.

Small typed contracts can declare positional `args`. Wider requests use an
explicit `input` map. Put defaults in the route or executable schema. Pass
caller context, timeout, and Signal envelope options through the generated API:

```elixir
{:ok, agent} = Jido.Examples.ParallelJoin.fetch_pair(server, 3)
signal = Jido.Examples.ParallelJoin.fetch_pair_signal!(3, :left)

{:ok, agent} =
  Jido.Examples.GroundedAnswer.answer(server, "Which source supports this?",
    input: %{resolve: true, allow_web: false},
    context: %{retriever: retriever, resolver: resolver, model: model},
    timeout: 5_000
  )
```

Custom functions remain when they verify signatures, set stable event IDs,
prepare continuation state, or adapt session results. Raising Signal constructors
use `!`. See the [interface review](../../docs/examples/example-interface-results.md)
and [authoring guide](../../docs/design/agent-dsl-interfaces.md).

## State, effects, and commit

Direct `cmd/3` returns a candidate Agent and Directives. An Action or Flow can
perform synchronous external work before returning. A failure preserves the
committed Agent but does not undo completed external work. Applications own
idempotency and recovery. State assembly is repeatable for fixed inputs and
executable results; external responses can change.

Directives request runtime operations or work after commit. Dispatch cannot
mutate committed Agent state; a result enters through another Signal. A Plugin
can dispatch typed Directives without a process. Both forms use Server-owned
tasks, validation, ordering, and failure handling. Basic proves these current
contracts. REC-01 separately proves explicit durable delivery through a Plugin.

## Basic feature group

Basic now proves SDK obligations with five fixtures and 22 tests:

| Source fixture | Main obligation |
| --- | --- |
| [Minimal Agent](01_basic/01_01_minimal_agent/minimal_agent.ex) | Direct/live agreement and instance isolation |
| [Typed Command Agent](01_basic/01_02_typed_command_agent/typed_command_agent.ex) | Construction, routing, input, and candidate validation |
| [Plugin State Agent](01_basic/01_03_plugin_state_agent/plugin_state_agent.ex) | State ownership and atomic commit |
| [Directive Agent](01_basic/01_04_directive_agent/directive_agent.ex) | Batch validation and post-commit dispatch order |
| [Controlled Turn Agent](01_basic/01_05_controlled_turn_agent/controlled_turn_agent.ex) | Serialization, cancellation, and caller timeout |

See the [suite](../../test/examples/01_basic/README.md) and
[current results](../../docs/examples/basic-results.md).
Each Basic command uses a typed Action. Minimal Agent keeps its small Action in
the route and does not add a Flow. Larger or reused Actions remain modules. See
the [beta.6 adoption report](../../docs/examples/inline-actions-expressions-results.md).
The invalid candidates, failing Directives, and execution barriers are deliberate
inputs that test SDK rejection and runtime behavior.

## Workflow feature group

Workflow now has nine source fixtures and 35 SDK integration tests. Each owns
a separate contract across Jido.Flow, Jido.Exec, and the Agent Server.

Short operations use inline bodies in Step, Reduce, Iterate, and Dispatch
slots. Keep bodies of more than about five lines in named Actions. Inline
Actions keep bindings beside the body; the Flow schema still validates input.
`Jido.Expr` supplies small calculations in data fields. See the
[adoption results](../../docs/examples/workflow-results.md#inline-action-and-expression-adoption).

| Fixture | Main obligation |
| --- | --- |
| [Sequential Flow](02_workflow/02_01_sequential_flow/sequential_flow.ex) | Input and output schemas, result dependencies, control dependencies, and one complete commit |
| [Effectful Steps](02_workflow/02_02_effectful_steps/effectful_steps.ex) | Transient caller context, effect guards, explicit output projection, idempotency, and persistence |
| [Conditional Routes](02_workflow/02_03_conditional_routes/conditional_routes.ex) | First-match Choice, lazy branch work, explicit failure capture, and selected-Action errors |
| [Parallel Join](02_workflow/02_04_parallel_join/parallel_join.ex) | Concurrent independent steps, join dependencies, execution limits, failure, and cancellation |
| [Ordered Batch](02_workflow/02_05_ordered_batch/ordered_batch.ex) | Ordered Map results, collected errors, fail-fast commit behavior, empty input, and serial Reduce |
| [Bounded Iteration](02_workflow/02_06_bounded_iteration/bounded_iteration.ex) | Initial completion, exact loop bounds, and validation of initial and replacement state |
| [Nested Flow](02_workflow/02_07_nested_flow/nested_flow.ex) | Separate child result scopes, shared context, child schemas, typed failures, and shared timeout |
| [Executable Continuation](02_workflow/02_08_executable_continuation/executable_continuation.ex) | Dispatch, shared context and continuation budget, terminal output validation, and timeout |
| [Approval Workflow](02_workflow/02_09_approval_workflow/approval_workflow.ex) | Separate approval Turns, post-commit Plugin dispatch, correlation, duplicates, and provider failure |

See the [Workflow SDK suite](../../test/examples/02_workflow/README.md),
[current results](../../docs/examples/workflow-results.md), and
[archived domain profiles](../../docs/examples/archive/workflow/README.md).
Caller context supplies adapters and observers. Tests use barriers to prove
ordering, concurrency, commit visibility, and worker termination. Approval
Workflow retains the flight-booking story and records every provider attempt.

## Minimal Agent

`Jido.Examples.MinimalAgent` uses the smallest path. One Signal selects one Action.
The Action returns the next Agent state. No Plugin or Flow is present.
The route supplies `%{amount: 1}` as a default. Empty Signal data uses it; a
supplied `amount` overrides it. Typed Command Agent also shows that supplied
nested maps replace route defaults before Action input validation.

Files:

- `lib/examples/01_basic/01_01_minimal_agent/minimal_agent.ex`
- `test/examples/01_basic/01_01_minimal_agent/minimal_agent_test.exs`

## LLM feature group

LLM has ten SDK fixtures and 66 integration tests. Each adds a capability to
the learning sequence. Clients stay in caller context and the tests record
actual model, tool, and retrieval inputs.

| Fixture | Main obligation |
| --- | --- |
| [Model Response](03_llm/03_01_model_response/model_response.ex) | One typed response, transient client context, selected persisted fields, and explicit fallback policy. |
| [Conversation History](03_llm/03_02_conversation_history/conversation_history.ex) | Actual history across Turns, duplicate rejection, and restore with a fresh client. |
| [Tool Call](03_llm/03_03_tool_call/tool_call.ex) | An approved name resolves to a typed Action; invalid input stops before tool effects. |
| [Tool Loop](03_llm/03_04_tool_loop/react_agent.ex) | Flow Dispatch and continuation carry model/tool rounds to one terminal commit. |
| [Parallel Tools](03_llm/03_05_parallel_tools/parallel_tools.ex) | Validate a complete tool plan, run concurrent Actions with Map, and retain call-ID order. |
| [Grounded Answer](03_llm/03_06_grounded_answer/grounded_answer.ex) | Retrieve evidence, generate an answer, and validate citation identity, revision, and page before commit. |
| [Output Repair](03_llm/03_07_output_repair/output_repair.ex) | Flow Iterate carries validation feedback through at most three model attempts. |
| [Context Compaction](03_llm/03_08_context_compaction/context_compaction.ex) | Compact committed history and retain recent and queued messages under an explicit byte limit. |
| [Subagent Delegation](03_llm/03_09_subagent_delegation/subagent_delegation.ex) | Spawn a real child Agent, transfer client context explicitly, and correlate result and failure Signals. |
| [Recursive Analysis](03_llm/03_10_recursive_analysis/recursive_language_model.ex) | Run the bounded application recursion tree under one Agent execution lifecycle. |

See the [LLM suite](../../test/examples/03_llm/README.md),
[results](../../docs/examples/llm-results.md), and
[research archive](../../docs/examples/archive/llm/README.md).
`Jido.Examples.ReActAgent` retains its module name under Tool Loop.
`Jido.Examples.RecursiveLanguageModel` retains its module name under Recursive Analysis.
The child-Agent example is `Jido.Examples.LLMSubagentDelegation`.

Run the LLM suite:

```shell
mix test --include integration test/examples/03_llm
```

Run the retained RLM stress command:

```shell
mix run lib/examples/03_llm/03_10_recursive_analysis/stress.exs \
  --records 100000 --leaf 64 --agents 4 --rounds 3
```

## Runtime feature group

Runtime has 13 fixtures and 93 passing tests with no skips. State Recovery
rejects stale persistence writes and retains the latest durable revision.

| Fixture | Added feature |
| --- | --- |
| [Scheduled Signals](04_runtime/04_01_scheduled_signals/scheduled_counter.ex) | A Scheduler Directive produces a later Signal and a separate commit. |
| [Keyed Timers](04_runtime/04_02_keyed_timers/burst_buncher.ex) | An example Plugin replaces one keyed timer, ignores stale generations, and flushes one ordered batch. |
| [Bus Delivery](04_runtime/04_03_bus_delivery/bus_delivery.ex) | A real Bus Client delivers ordered records, retries failed Turns, and acknowledges after commit. |
| [Managed Jobs](04_runtime/04_04_managed_jobs/managed_jobs.ex) | An Agent-owned Plugin starts a linked task after commit and sends a later terminal Signal. |
| [Runtime Inspection](04_runtime/04_05_runtime_inspection/agent_live_debugger.ex) | Public inspection exposes committed state and its matching revision while work is active. |
| [State Recovery](04_runtime/04_06_state_recovery/persistent_counter_recovery.ex) | A restored Agent retains its complete state, duplicate ledger, and commit revision. |
| [Input Deduplication](04_runtime/04_07_input_deduplication/deduplicating_inbox.ex) | A stable input ID rejects duplicate work before a new commit; invalid input consumes no ID. |
| [Commit Outbox](04_runtime/04_08_commit_outbox/audit_outbox.ex) | Business state and audit intent restore together; manual sink delivery can safely repeat. |
| [Agent Observation](04_runtime/04_09_agent_observation/turn_observation.ex) | SDK telemetry reports lifecycle, Turns, commits, and terminal outcomes. |
| [Causal Trace](04_runtime/04_10_causal_trace/causal_trace.ex) | Child creation and work retain trace and cause identities across nodes. |
| [Recoverable Delivery](04_runtime/04_11_recoverable_delivery/recoverable_delivery.ex) | A Plugin resumes committed delivery intent after loss. |
| [Pending Job Recovery](04_runtime/04_12_pending_job_recovery/pending_job_recovery.ex) | Approval, retry, cancellation, and attempt identity survive restart. |
| [Durable Scheduling](04_runtime/04_13_durable_scheduling/scheduled_occurrence_recovery.ex) | Saved occurrences retry until their business result commits. |

Run `mix test --include integration test/examples/04_runtime`.
See the [group guide](04_runtime/README.md).

## Multi-agent feature group

Multi-agent has six fixtures and 38 passing tests. All use real child Agents.

| Fixture | Added feature |
| --- | --- |
| [Child Lifecycle](05_multi_agent/05_01_child_lifecycle/child_lifecycle.ex) | A parent starts real children, tracks a restarted PID with the same ID, and stops owned processes. |
| [Correlated Requests](05_multi_agent/05_02_correlated_requests/correlated_requests.ex) | Pending parent state, independent child work, and a later correlated reply form separate Turns. |
| [Bounded Workers](05_multi_agent/05_03_bounded_workers/bounded_workers.ex) | At most eight live children reuse fixed slots; each result admits one queued item and results retain input order. |
| [Agent Hierarchy](05_multi_agent/05_04_agent_hierarchy/agent_hierarchy.ex) | Each Agent owns direct children; branch loss is isolated and root shutdown removes the whole subtree. |
| [Remote Child](05_multi_agent/05_05_remote_child/remote_child.ex) | A parent places and owns a child on a selected Erlang node. |
| [Remote Lifecycle](05_multi_agent/05_06_remote_lifecycle/remote_lifecycle.ex) | Disconnect, node loss, parent loss, and replacement have explicit outcomes. |

Run `mix test --include integration test/examples/05_multi_agent`.
See the [group guide](05_multi_agent/README.md).

The [result report](../../docs/examples/runtime-multi-agent-results.md) records
verification. The [gap register](../../docs/examples/runtime-multi-agent-gaps.md)
separates core contract questions from application and adapter work.
[Research](99_research/README.md) is a queue of eight unresolved capabilities.
Start with the [capability ledger](../../docs/examples/research-capabilities.md).
The old application sketches remain available in the documentation archive and
Git history at commit `bd05a32`.

## Factory feature group

Factory adds four runnable stages: a live ReqLLM conversation, a three-Agent
system with IEx chat and model tools, a factory with four department heads,
and a [larger Flow across nine worker Agents](06_factory/06_04_flow_factory/README.md).
The model calls use `req_llm` directly. Tests replace the HTTP boundary and
exercise real provider encoding, Agent turns, Signals, and owned tasks.

See the [Factory guide](06_factory/README.md) for key setup and launch commands,
and the [orchestrator plan](06_factory/orchestrator-plan.md) for the larger system.

```sh
mix test --include integration test/examples/06_factory
```

## Initial pressure results

- The simple Action path is small and direct.
- `Jido.Flow` can own a complete effectful Agent Turn without adding Agent
  callbacks or intermediate Agent commits.
- Directives work well as commands from an Action to runtime machinery.
- Plugins own custom Directive types and validation. Command callbacks, owned
  state, and a runtime process are optional. Directive Agent proves both process
  forms, and Approval Workflow no longer needs a separate booking runtime module.

## Topology feature group

[Topology examples](07_topology/README.md) define independent Agents, logical
parent/child trees, a Bus swarm with 1000 workers, and keyed account Agents.
They use equal Spark DSL, Builder, and JSON forms through a Codec. A fifth
example composes two teams with public exports and a shared Bus. The guide
includes application boot, readiness, repair, and shutdown.
