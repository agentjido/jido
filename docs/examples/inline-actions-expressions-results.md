> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# Inline Actions and expressions

Latest run: **2026-09-04**.

The active examples use the Hex package `jido_action` **3.0.0-beta.6**. This
release supplies `Jido.Expr` and portable inline Actions for Flow slots. Jido
also adopts the public inline Action compiler in the Agent route DSL.

## Agent route form

Minimal Agent now keeps its complete operation beside the route:

```elixir
route "basic.minimal.increment" do
  action %{amount: amount},
    name: "examples_minimal_agent_increment",
    schema: Zoi.object(%{amount: Zoi.integer()}),
    context: context do
    {:ok, %{context.agent_state | count: context.agent_state.count + amount}}
  end

  defaults %{amount: 1}
  define :increment, args: [{:optional, :amount}]
end
```

This Agent does not need a Flow. The body compiles to an ordinary Action. It
uses normal Action schemas, `Jido.Exec`, telemetry, errors, timeout, and
cancellation. `MinimalAgent.route_action("basic.minimal.increment")` returns
the target for Builder or Codec Registry use.

The Agent DSL rejects a missing target, a named target plus an inline body,
more than one inline body, and Flow binding syntax in a route callback. The
authoring tests cover direct execution, live execution, Builder reuse, and a
Codec round trip.

## Flow forms

The Workflow examples now use nested inline Actions in Step, Reduce, Iterate,
and Dispatch decision slots. The LLM examples add small Step Actions with
schemas and caller context. Named Actions remain when a target is reused, has
several callback clauses, or contains more than about five lines of policy.

For example, Ordered Batch keeps its shared `Convert` Action for two Map slots
and puts the single-use reducer in its Reduce block. Executable Continuation
puts the small decision in Dispatch and keeps its multi-clause expander and
continuation Action as modules.

Sequential Flow uses an expression in a binding:

```elixir
action value <- input(:value) * 2, context: ctx do
  Observation.record(ctx, :double, %{value: value})
  {:ok, %{value: value}}
end
```

The Builder test creates the same calculation with
`Jido.Expr.new!(:multiply, [Builder.input(:amount), 2])`. Codec emits and reads
the version 2 expression form. The decoded Flow returns the same result.

## Example coverage

The review applies the same rule to all active groups:

| Group | Applied form |
| --- | --- |
| Basic | One route-only state change is inline. Larger state, Directive, and control policies remain named. |
| Workflow | Short Step, Reduce, Iterate, and Dispatch work is inline. Reused and multi-clause targets remain named. |
| LLM | Small selection, generation, output projection, append, and lifecycle operations are inline. Provider and validation policies remain named. |
| Runtime | Small scheduling, inspection, observation, and delivery operations are inline. Recovery policies and shared targets remain named. |
| Multi-agent | Small stop, record, and lifecycle updates are inline. Spawn, request, and worker policies remain named. |
| Research | The remaining DIST-03 probe uses an inline record route. Its ownership gap is unchanged. |

## Verification

The active example command passes all **170 tests**:

```shell
mix test test/examples/01_basic test/examples/02_workflow \
  test/examples/03_llm test/examples/04_runtime test/examples/05_multi_agent \
  --include example --seed 0
```

The focused Agent authoring suite passes **24 tests**. The broader checks are:

| Check | Result |
| --- | --- |
| Active example groups | 170 passed |
| Agent, observation, and Plugin tests without research | 388 passed; 2 excluded |
| Default suite without research | 697 passed; 184 excluded |
| DIST-03 research probe | 1 revision-fence proof passed; 1 cluster-owner assertion failed as designed |
| `mix quality` | Passed; no application warnings, Credo issues, or Dialyzer findings |
| Documentation build | Passed |
| Local Markdown links | 230 files checked; no broken local links |

The test compiler reports existing type warnings in negative-input tests. The
application compilation with warnings as errors passes. The DIST-03 failure is
the open distributed authority question; this change does not hide or alter it.
