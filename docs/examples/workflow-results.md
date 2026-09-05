> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# Workflow SDK integration results

Latest run: **2026-09-04**.

Workflow now has **nine source fixtures, nine matching test folders, and 35
passing integration tests**. All 17 previous source/test folders were removed.
Their [research profiles](archive/workflow/README.md) preserve the source
attribution and map each domain example to its replacement.

| Order | Fixture | Tests passed | SDK obligation |
| --- | --- | ---: | --- |
| 02_01 | Sequential Flow | 4 | Flow schemas, dependencies, candidate validation, one commit, and compiled Step reuse |
| 02_02 | Effectful Steps | 3 | Transient context, guarded effects, late failure, output projection, duplicate revisions, persistence and restore |
| 02_03 | Conditional Routes | 3 | First match, lazy branches, explicit expected-error capture, selected-Action failure |
| 02_04 | Parallel Join | 5 | Actual overlap, concurrency limit, join dependency, failure, worker cancellation and queued work |
| 02_05 | Ordered Batch | 4 | Reverse completion, positional errors, fail-fast rejection, serial Reduce, empty collections |
| 02_06 | Bounded Iteration | 3 | Initial completion, exact final bound, exhaustion, initial/replacement state validation |
| 02_07 | Nested Flow | 4 | Child result scope, shared context, child schemas, typed error, shared timeout |
| 02_08 | Executable Continuation | 4 | Flow Dispatch, shared context/budget, terminal validation, complete-chain timeout |
| 02_09 | Approval Workflow | 5 | Post-commit dispatch, valid stale revision, duplicate attempts, result correlation, provider failure |
| Total | | 35 | No skipped Workflow cases |

See the [suite and acceptance cases](../../test/examples/02_workflow/README.md).

## Inline Action and expression adoption

The current examples use `jido_action` **3.0.0-beta.6**. Small operations use
portable inline Actions in all supported Flow roles where this makes the code
clear. Inputs and caller context stay explicit beside each body.

| Fixture | Inline roles | Named Actions retained |
| --- | --- | --- |
| Sequential Flow | Step `double` and Step `gate` | `Finish` has a larger body |
| Effectful Steps | Step `guard` | `Read` and `Project` have multiple clauses and larger bodies |
| Conditional Routes | Step `fetch` | `Select` is reused by four Choice branches |
| Parallel Join | Step `join` | Both branches reuse the larger `Fetch` Action |
| Ordered Batch | Reduce `append` | Two Flows reuse the validated Map `Convert` Action |
| Bounded Iteration | Iterate `repair` | No separate body Action is needed |
| Nested Flow | None | The reusable child Flow and larger `Write` Action stay named |
| Executable Continuation | Dispatch decision | The multi-clause expander and continuation Action stay named |
| Approval Workflow | None | Search and booking policies stay named |

Sequential Flow also uses `Jido.Expr` in the Action binding:

```elixir
step "double" do
  action value <- input(:value) * 2, context: ctx do
    Observation.record(ctx, :double, %{value: value})
    {:ok, %{value: value}}
  end
end
```

The Flow input schema validates the integer before expression evaluation. The
compiled Action receives the calculated `value`. `Pipeline.step_action/1`
returns that ordinary Action target. The Builder test supplies a new
`Jido.Expr.new!/2` binding, executes it, encodes it as JSON version 2, decodes
it, and executes it again.

The output schema and Agent candidate schema keep their separate validation
boundaries. Actions with more than about five lines, several callback clauses,
or use in several slots remain named modules.

## Current verification

- All five active example groups: **170 passed**, with no skips.
- Agent, observation, and Plugin tests without research: **388 passed**.
- Default suite without research: **697 passed**, with 184 tagged tests excluded.
- Formatting, application compilation with warnings as errors, Credo,
  Dialyzer, documentation generation, and local Markdown links: passed.
- The ordered-batch test checks beta.6's fail-fast admission contract with
  an execution barrier. The first admitted item fails in any ready order;
  pending items do not start, Reduce does not run, and committed state is preserved.

```shell
mix test --include example --include integration test/examples/01_basic \
  test/examples/02_workflow --seed 0
```

## Initial SDK fixture verification — 2026-09-03

- Before replacement: the 17 old examples passed all 44 tests under the current
  dependency version.
- Each of the nine new folders was tested separately with
  `mix test --include integration test/examples/02_workflow/02_NN_name --seed 0`.
  Every folder passed, with the counts shown above.
- `mix test --include example --seed 0`: **768 passed, 36 skipped, 11 excluded**.
  This includes Basic, Workflow, the other examples, and core tests in the current
  shared checkout. The skips and excluded advanced cases are outside Workflow.
- `mix compile --warnings-as-errors`: passed.
- `mix format --check-formatted`, `git diff --check`, and local Markdown links: passed.
- Final combined Basic and Workflow run: **48 passed** (15 Basic and 33 Workflow).
- Documentation generation through `Mix.Tasks.Docs.run([])`: passed.
- The commit includes `jido_action` **3.0.0-beta.4** and its Flow formatter
  support. The beta.3-to-beta.4 change does not alter the execution runtime.
  This refactor does not change core SDK implementation.

The wider test run reports existing type warnings from deliberately invalid
inputs in negative tests. No Workflow case is skipped or has a separate failure
exclusion tag. The separately excluded advanced integration group was not rerun.

## What the tests now prove

Tests import source Agents, Actions, Flows, and Plugins. Real Signal routing,
Jido.Exec, Flow scheduling, schemas, Server commits, persistence, and Directive
dispatch perform the work. An optional observation callback in caller context
records Action entry and holds test barriers. It does not replace execution.
Tests monitor real workers and use public Server status and snapshot APIs.

The concurrency tests require both workers to enter before either is released.
Collection tests force reverse completion. Reduce accumulates the ordered
sequence rather than a sum that could hide reordering. Held stages expose the
previous committed Agent snapshot. Failure cases preserve existing non-default
state. Cancellation proves that both active Flow workers stop and queued work
uses fresh context.

Input schema rejection executes no Action. Output schema rejection happens
after execution, before Agent candidate validation and commit. A child Flow
keeps its own schema boundary. Iterate checks both initial and replacement
state. Continuation uses one budget for the complete Flow/Action chain.

## Current Map behavior

The installed SDK collects Map errors as `%{status: :error, error:
%{message: ...}}`. It keeps input position but does not retain the full typed
Action error map. The test asserts the current public payload and positional
association. Retaining typed details is a separate possible SDK improvement.

`:fail_fast` rejects the complete batch and prevents the dependent Reduce.
In beta.6, a failed runnable stops pending work from starting. Already admitted
concurrent work can finish. At concurrency one, no next item starts after the
failure. The batch test checks this without assuming a particular ready order;
the Parallel Join test separately checks that admitted concurrent work can finish.

## Preserved and strengthened application boundaries

Effectful Steps retains Weather Lookup's direct/live agreement, transient
adapter context, isolation between Turns, unchanged successful commit revision,
actual persisted record, and restoration. A guard prevents an adapter call; a
later revision check cannot undo an external call. A provider failure returns
a typed error without replacing the prior commit. Output fields are selected
explicitly by application code; the SDK does not automatically redact data.

Approval Workflow retains the flight-booking story. Search and booking adapters
now both arrive in caller context. The typed booking Directive has only request
and idempotency key fields. Its process-free Plugin reads the committed snapshot
before it calls the provider. Provider results enter through normal Signals.

The stale-selection test uses revision 1 after a second search creates revision
2. Both pass input validation, so the test reaches the actual revision policy.
The provider recorder counts every attempted call before deduplication. A queued
duplicate approval causes no second attempt. Result handlers accept a matching
key only while submitting; stale and duplicate terminal results cannot replace
a completed booking. An accepted unchanged result still advances the commit
revision. Provider failure completes in a separate fourth Turn.

These are local SDK tests. They do not claim live provider coverage, automatic
external rollback, durable booking recovery, or SDK-owned business policy.
