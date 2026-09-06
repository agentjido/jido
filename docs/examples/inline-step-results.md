> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# Inline Step adoption

This report records the earlier beta.5 probe. The
[current beta.6 adoption](inline-actions-expressions-results.md) adds
`Jido.Expr`, expanded Flow inline Actions, and Agent route inline Actions.

Date: **2026-09-04**. Scope: **Basic compatibility and Workflow inline Steps**.

## Dependency

`mix.exs` and `mix.lock` use
[`jido_action` 3.0.0-beta.5 from Hex](https://hex.pm/packages/jido_action/3.0.0-beta.5).
The exact version requirement is `== 3.0.0-beta.5`. This replaces the temporary
Git pin to `043f5ca9b133168fe21d53071161e205e01ce7cf` from
[PR #220](https://github.com/agentjido/jido_action/pull/220).
The 60 library source files and formatter config match that PR revision.
Other dependency versions are unchanged.

## Basic authoring

All Basic commands use typed Actions. Minimal Agent increments a count in one
Action. The profile command applies and normalizes its patch in one Action.
Neither operation needs a Flow. The remaining commands also keep their Actions
and their existing Directive contracts.

Minimal Agent's body remains:

```elixir
@impl Jido.Action
def run(%{amount: amount}, %{agent_state: state}) do
  {:ok, %{state | count: state.count + amount}}
end
```

The Agent DSL still defines routes, defaults, command helpers, and Signal
constructors. Action schemas validate input. The Agent schema validates the
complete candidate before commit. Invalid Action input still returns
`Jido.Action.Error.InvalidInputError` through direct and live execution.

Use inline Step bodies where a Flow already expresses a required workflow.
Do not add a Flow only to demonstrate inline syntax. This Basic run proves
compatibility with the Hex release; it does not exercise inline Step bodies.

## Workflow adoption

Five short Steps in existing Flows now have inline bodies: Sequential Flow's
`double` and `gate`, Effectful Steps' `guard`, Conditional Routes' `fetch`, and
Parallel Join's `join`. Larger bodies stay in named Actions. Map, Reduce,
Iterate, Choice, and Dispatch keep their supported callback forms.

All **35 Workflow tests pass**. Tests also prove reuse of a compiled inline
Step with new Builder bindings and a JSON round trip. See the
[Workflow results](workflow-results.md#inline-step-adoption) for the syntax,
selection rule, and complete test evidence.

## Current Basic results

All **22 Basic tests pass** with Hex `3.0.0-beta.5`, with no skips:

```shell
mix test --include example --include integration test/examples/01_basic --seed 0
```

The original 20 tests remain. Two additional cases check invalid counter input
and recovery, and profile-patch execution across Spark, map, keyword, Builder,
and JSON Agent construction. Tests use real Agent Servers and generated command
helpers. Existing checks cover Plugin ownership, Directive validation and
ordering, cancellation, queued commands, and caller timeout behavior.

The local runtime is Elixir **1.20.3** and OTP **29**.
Formatting and test-environment compilation with warnings as errors pass
with the Hex package.

## Earlier wider dependency check

The dependency review run had **814 passed, 2 failed, 35 skipped**. Its
failures were the Fixed Group and Elastic Group cases. See the
[checkpoint](checkpoint.md) for the current results after example
reorganization and the persistence fix.

Before restoring the Basic Actions, two full probe runs with seed 0 returned
**809 passed, 3 failed, 35 skipped**. These are historical results, not a full
suite run of the current Basic revision.

Two failures are the Fixed Group and Elastic Group cases already recorded in
the [checkpoint](checkpoint.md). The additional failure is
`test/examples/02_workflow/02_05_ordered_batch/ordered_batch_test.exs:68`.

The PR branch also contains upstream commit
[`27a5c87`](https://github.com/agentjido/jido_action/commit/27a5c877fff90266335b71bfdc17aaded2e133b3),
which stops pending Flow work after a failure. This commit is absent from
`v3.0.0-beta.4`. The earlier Workflow test assumed that all ready items run even
after the first failure. It passed in isolation, but both full runs exposed
the outdated assumption. The Workflow adoption now replaces that assumption
with an execution barrier that proves pending items do not start after failure.
The updated test passes in both the focused and full runs.

The current `mix quality` run passes formatting, compilation with warnings as
errors, the configured Credo check, and Dialyzer with **zero findings**.
The six findings listed in the checkpoint are fixed without suppressions.
The current documentation build passes without warnings.

The fixes remove unreachable branches in Directive validation, Plugin runtime
startup, persistence, and cron startup. The Plugin admission validator now uses
its actual callback name and arity. Validation at public boundaries remains in
place. Three new tests check invalid persistence replies, ignored Plugin runtime
startup, and Plugin admission errors. The persistence fault test also checks
load and delete failures. All these tests pass in the full run. That run still
emits five existing compiler warnings from test files.

## Files

- [Minimal Agent](../../examples/01_basic/01_01_minimal_agent/minimal_agent.ex)
- [Typed Command Agent](../../examples/01_basic/01_02_typed_command_agent/typed_command_agent.ex)
- [Authoring tests](../../test/examples/01_basic/authoring_formats_test.exs)
- [Basic test guide](../../test/examples/01_basic/README.md)
