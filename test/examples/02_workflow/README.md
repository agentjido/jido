# Workflow SDK integration tests

Workflow has nine source fixtures and 35 enabled SDK integration tests. It
replaces the 17 domain examples and their 44 repeated acceptance tests.
Each test imports the real example. No test defines replacement SDK components.

| Order | Fixture | Tests | SDK obligation |
| --- | --- | ---: | --- |
| `02_01_sequential_flow` | [Sequential Flow](02_01_sequential_flow/sequential_flow_test.exs) | 4 | Schemas, dependencies, one complete commit, and compiled Step reuse through Builder and JSON |
| `02_02_effectful_steps` | [Effectful Steps](02_02_effectful_steps/effectful_steps_test.exs) | 3 | Transient caller context, effect guards, explicit output projection, idempotency, and persistence |
| `02_03_conditional_routes` | [Conditional Routes](02_03_conditional_routes/conditional_routes_test.exs) | 3 | First-match Choice, lazy branch work, explicit failure capture, and selected-Action errors |
| `02_04_parallel_join` | [Parallel Join](02_04_parallel_join/parallel_join_test.exs) | 5 | Concurrent independent steps, join dependencies, execution limits, failure, and cancellation |
| `02_05_ordered_batch` | [Ordered Batch](02_05_ordered_batch/ordered_batch_test.exs) | 4 | Ordered Map results, collected errors, fail-fast commit behavior, empty input, and serial Reduce |
| `02_06_bounded_iteration` | [Bounded Iteration](02_06_bounded_iteration/bounded_iteration_test.exs) | 3 | Initial completion, exact loop bounds, and validation of initial and replacement state |
| `02_07_nested_flow` | [Nested Flow](02_07_nested_flow/nested_flow_test.exs) | 4 | Separate child result scopes, shared context, child schemas, typed failures, and shared timeout |
| `02_08_executable_continuation` | [Executable Continuation](02_08_executable_continuation/executable_continuation_test.exs) | 4 | Dispatch, shared context and continuation budget, terminal output validation, and timeout |
| `02_09_approval_workflow` | [Approval Workflow](02_09_approval_workflow/approval_workflow_test.exs) | 5 | Separate approval Turns, post-commit Plugin dispatch, correlation, duplicates, and provider failure |

Run the full batch:

```shell
mix test --include integration test/examples/02_workflow --seed 0
```

Run one fixture by passing its folder instead. These tests also run in
`mix examples` and `mix test --only integration`. Each has `:example`,
`:integration`, and `group: :workflow` tags. Failed obligations remain enabled.

## Integration boundary

Jido routes a Signal, supplies caller context, starts Jido.Exec, validates the
complete candidate, and commits it. Jido.Flow and Jido.Exec from jido_action
own graph scheduling, schemas, collections, loops, and continuation. The tests
exercise these real components together.

The [shared controls](../../support/workflow_sdk_case.ex) observe Action entry,
hold explicit barriers, and monitor worker exit. Source observation uses an
optional callback in caller context. Tests use no fixed sleeps, private Server
messages, or replacement execution engines. Domain operations use Signals.
The effect adapter records every call; it does not hide duplicate attempts.

## Strong acceptance cases

- Compiled inline Steps can be reused with `Jido.Expr` bindings through Builder
  and stored JSON alongside named Actions.
- A held step exposes the prior complete snapshot. Success advances one revision.
- An explicit `after:` dependency blocks a step without copying the gate result.
- Invalid Flow input runs no Action; invalid Flow output and Agent candidates
  fail at their own schema boundary.
- Context reaches Flow steps, stays isolated between Turns, and is absent from
  persisted state. The actual commit record is loaded and restored.
- A guard blocks the external call. A later validation error does not undo a call.
- Two matching Choice options select only the first. Selected failure does not
  enter `otherwise`. Expected provider failures become data by explicit policy.
- Independent workers overlap at limit two and stay serial at limit one.
- Cancellation stops both workers and preserves fresh context for queued work.
- Reverse item completion preserves source order and error position. Reduce
  records the complete sequence, so a reordered fold cannot pass as a sum could.
- At concurrency one, the first item failure stops pending items from starting
  and prevents Reduce. An execution barrier makes the test independent of ready order.
- Initial Iterate completion invokes no body. The final allowed repair succeeds;
  exhaustion invokes exactly three bodies. State validation stops the next body.
- Two uses of the same child Flow keep separate results and share caller context.
  Child input, output, failure, and timeout propagate through the parent.
- One continuation budget and execution timeout cover the complete chain.
- Approval exposes the committed submitting state before the adapter call.
  Duplicate approval makes no second provider attempt. Stale and duplicate
  result Signals cannot replace terminal state.

## Current execution details

Map `:collect_errors` returns positional records. Its error payload currently
contains only `message`; it does not preserve the full typed Action error map.
A `:fail_fast` Map rejects the complete Turn and prevents its dependent Reduce.
In beta.6, a failure stops pending work from starting. Already admitted concurrent
work can finish. The batch test checks that a failure at concurrency one starts
no next item. Parallel Join separately checks admitted concurrent work.

A successful duplicate request or ignored result Signal still creates a commit
revision when its Action returns unchanged state. Provider idempotency and
approval/correlation rules are application policy. The approval handler accepts
a matching result only while submitting. No durable booking recovery is claimed.

## Scope and migration

Use inline Action bodies for small operations of about four or five lines.
Larger bodies stay in named Actions. The suite uses inline Steps in Sequential
Flow, Effectful Steps, Conditional Routes, and Parallel Join. Ordered Batch uses
an inline Reduce Action. Bounded Iteration uses an inline Iterate Action.
Executable Continuation uses an inline Dispatch decision. Reused Map and Choice
targets and the multi-clause Dispatch expander stay in named Actions.

Sequential Flow calculates its bound value with `Jido.Expr`. Its Builder test
constructs the same expression through `Jido.Expr.new!/2`, then checks a stored
JSON round trip. This proves the module DSL, Builder, and Codec forms.

The [source folders](../../../lib/examples/02_workflow) match these nine test
folders. The [research archive](../../../docs/examples/archive/workflow/README.md)
maps every old domain profile to its replacement. Arithmetic, scoring, SQL
policy details, citations, and output wording do not need separate SDK fixtures.
Weather's direct/live comparison, context isolation, duplicate revision, real
persistence record, and restore checks now live in Effectful Steps.

See the [result report](../../../docs/examples/workflow-results.md).
