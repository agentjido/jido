> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# Agent DSL migration results

Run date: **2026-09-04**. Baseline checkpoint: `39c06d1`.

This report records the initial migration. The later
[interface review](example-interface-results.md) removes redundant Signal aliases,
adds domain command names, and records current verification. The code examples
below use the current API.

All example Agent declarations now use Spark blocks. This migration converts
74 Agents in the remaining numbered examples and 16 Agents in integration
fixtures. Together with the five Basic Agents, all 95 declarations use the DSL.
The 78 catalog profiles include one additional LLM child Agent.

## Preserved behavior

The migration moves schemas, metadata, and Plugins into `agent do ... end`.
Ordered routes move into `routes do ... end`. Names and descriptions remain
options on `use Jido.Agent`.

A comparison of the parsed declarations against the checkpoint confirmed the
same names, descriptions, schemas, metadata, Plugin configuration and order,
and route targets and order for all 95 Agents. Action and Flow execution code,
runtime setup, and custom command preparation retain their existing behavior.

Thirteen simple Workflow and LLM Signal helpers now use explicit nested
`define` declarations. Their existing `signal` functions still return a Signal
and preserve their defaults. Generated constructors also provide tagged and
bang forms, and generated live helpers accept caller context and timeout options.

```elixir
alias Jido.Examples.ModelResponse

{:ok, signal} = ModelResponse.generate_signal("hello")
signal = ModelResponse.generate_signal!("hello")

{:ok, agent} =
  ModelResponse.generate(server, "hello", context: %{model: model_client})
```

Positional arguments require named executable input fields. Flows without
those fields accept an explicit input map:

```elixir
{:ok, agent} =
  Jido.Examples.NestedFlow.draft_and_review(server, input: %{text: "draft"})
```

Dynamic Signal types, signatures, adapter preparation, and other custom input
logic remain ordinary functions. The migration does not add input schemas to
Actions or change their validation rules.

## Verification

The example suite passes **201 tests**, with the same **35 skipped cases**.
The skips remain visible and do not represent completed SDK contracts.
Existing tests now exercise generated live calls for typed Workflow input,
explicit input maps, and LLM caller context, in addition to the preserved APIs.

The full run passes **807 tests**, with **two existing group failures** and
**35 skips**, matching the checkpoint. A run during concurrent compilation
also hit two 100 ms assertions in unchanged core tests. Both pass in the full
rerun without concurrent compilation or test changes.

Commands:

```shell
mix test --include example --include integration test/examples --seed 0
mix test --include example --include integration --seed 0
mix quality
mix docs --no-open
git diff --check
```

Formatting, compilation with warnings as errors, the configured Credo check,
and ExDoc pass. Dialyzer retains the six findings listed in the
[checkpoint](checkpoint.md). The Fixed Group and Elastic Group integration
failures from that checkpoint remain separate work.
