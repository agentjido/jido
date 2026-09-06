> Implementation notes and deferred extensions. Review status is pending approval.
> For the supported API, see [the current core scope](../../guides/core-scope.md).

# Agent Spark DSL and authoring formats

- Implementation: Implemented on the current SDK.
- Review: Pending approval.
- Related: [Agent authoring](authoring.md), [Agent](agent.md), and
  [Basic SDK tests](../../test/examples/01_basic/README.md).

This implementation adds Spark block authoring, route interfaces, runtime
builders, and authoring Codecs to the existing definition/instance and Agent
Server contracts. All numbered examples and integration example Agents use
the DSL. See the [migration results](../examples/agent-dsl-results.md).
The versioned-module, separate Plugin-state, and Ref-first changes in the wider
v3 design remain separate work.

## Spark syntax

```elixir
defmodule MyApp.Counter do
  use Jido.Agent, name: "counter"

  agent do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    metadata %{owner: :support}
    plugin MyApp.AuditPlugin, config: %{limit: 10}
  end

  routes do
    signal_source "/counters"

    route "counter.increment" do
      action %{amount: amount},
        name: "counter_increment",
        schema: Zoi.object(%{amount: Zoi.integer()}),
        context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + amount}}
      end

      defaults %{amount: 1}
      priority 10
      define :increment, args: [{:optional, :amount}]
    end

    route "system.*", MyApp.HandleSystem
  end
end
```

`agent` contains the domain schema, metadata, and ordered Plugin declarations.
`routes` contains ordered routes and the default source for generated Signals.
A route supports `defaults`, `priority`, and an external unary `match` capture.
A nested `define` explicitly requests helper functions. Several definitions can
share one route; a route without `define` creates no helpers. There is no
separate route alias or `code_interface` block.

## Inline route Actions

A route can contain one inline Action instead of a target module. The route
passes the complete prepared input map to the Action callback. The callback
pattern, schemas, metadata, and `context:` binding use the public
`Jido.Action.Inline` contract from `jido_action` 3.0.0-beta.6.

The body compiles to an ordinary Action module. It uses the same validation,
execution, telemetry, timeout, cancellation, and error contracts as a named
Action. The route does not store code or call an anonymous function at runtime.
`route_action/1` returns the compiled target when a Builder, direct Agent value,
or Codec Registry must reuse it:

```elixir
target = MyApp.Counter.route_action("counter.increment")

agent =
  Jido.Agent.Builder.new(name: "built_counter")
  |> Jido.Agent.Builder.schema(MyApp.Counter.schema())
  |> Jido.Agent.Builder.route("counter.increment", target, defaults: %{amount: 1})
  |> Jido.Agent.Builder.build!()
```

Inline route Actions use callback patterns such as `input` or
`%{amount: amount}`. They do not accept Flow bindings such as
`amount <- input(:amount)`. A route must contain one inline Action or name one
external target. It cannot do both. Action schemas do not infer fields or
defaults from the callback pattern.

Use this form for a small Action that belongs to one route. Keep a named Action
when several routes reuse it, when it has several callback clauses, or when its
policy is easier to read as a separate module. The active examples apply this
rule in Basic, LLM, Runtime, Multi-agent, and the remaining research probe.

Plugin `config` accepts a map or keyword list and becomes current SDK Plugin
options. Keyword order is preserved; map options use sorted keys. The module
identifies the Plugin, and each module can appear only once. The state key
comes from `state_spec/1`. Plugin declarations do not accept `as:` labels.

Agent route defaults use `defaults` in Spark blocks, Builder options, direct
route maps and keyword options, and Codec route records. `params` is not an
Agent route option. Flow step `params` retains its existing meaning.

The compiler stores normalized declarations in internal `__agent_config__/0`
and interface metadata in `__agent_interfaces__/0`. Source locations and
interface metadata do not enter the Agent or a checkpoint. Existing generated
accessors and overridable Agent callbacks remain available.

Keyword-only declarations remain supported. A field cannot be supplied in both
keyword and block form. Both forms use the same construction validation.
Block declarations receive compile-time validation; dependent executable
checks run after module verification to support Actions declared later
in the same file.

## Generated interface

```elixir
{:ok, signal} = MyApp.Counter.increment_signal(2)
signal = MyApp.Counter.increment_signal!(2)

{:ok, committed} =
  MyApp.Counter.increment(server, 2,
    timeout: 5_000,
    context: %{request_id: "request-1"}
  )

{:ok, candidate, directives} = MyApp.Counter.cmd(agent, signal)
```

Each `define` produces a tagged Signal constructor, its bang variant, and one
live call helper. Live helpers accept the current `Server.call/3` target and
preserve its results, errors, and OTP exits. Caller timeout stops waiting and
does not cancel the Turn. Named calls do not accept immutable Agent values;
direct execution stays explicit through `cmd/3`.

Rules:

- `args` lists top-level executable input names. Required arguments precede
  optional arguments. Optional list or keyword inputs use `input` options so
  they cannot be confused with the final keyword options.
- Omitted optional inputs remain absent. Explicit zero, false, and nil are
  preserved. The route applies its normal shallow defaults before executable
  validation; generated helpers do not duplicate these defaults.
- Additional payload fields use `input: %{...}`. A key cannot be supplied both
  positionally and in `input`.
- Envelope options use `signal: [...]`. The Signal type and data cannot be
  overridden through envelope options. Each constructor generates a fresh ID
  unless the caller supplies one. Signal time follows the Signal constructor's
  existing behavior and is not inferred.
- `context` and `timeout` are live-call options and never enter Signal data.
  Unknown or duplicate options return structured errors.
- Signal constructors validate packaging and the envelope. They do not run
  Plugin preparation, Action validation, executable work, or runtime work.
  A valid Signal can still produce a command error.
- `define` requires an exact route without a match predicate. Duplicate exact
  types cannot expose interfaces. Raw wildcard, predicate, and deliberately
  ambiguous routes retain current routing behavior.
- Interface names and all generated arities must be unique and must not
  overwrite manual functions or the Agent API.

The existing Basic `increment_signal/1` caller changed to the tagged form;
callers that need a direct Signal use `increment_signal!/1`. Generated helpers
accept keyword options, including `timeout: value`, rather than a bare timeout.

Generated documentation shows the input names and all supported arities:

```elixir
increment(server)
increment(server, amount_or_opts)
increment(server, amount, opts)

increment_signal()
increment_signal(amount_or_opts)
increment_signal(amount, opts)
```

An `amount_or_opts` argument accepts either the optional input or a keyword
options list. Required input arguments retain their field names. Names that
cannot be Elixir variables receive safe names; collisions receive suffixes.
The documentation lists the original payload fields in declaration order.

Generated specs describe the result of each helper. Raw payload input remains
`term()` because Plugin preparation can convert input before Action or Flow
validation. The final options argument has type `keyword()`; live helpers use
`Jido.AgentServer.server()` for the Server argument.

```elixir
@spec increment_signal(term(), keyword()) ::
        {:ok, Jido.Signal.t()} | {:error, term()}

@spec increment_signal!(term(), keyword()) :: Jido.Signal.t()

@spec increment(Jido.AgentServer.server(), term(), keyword()) ::
        {:ok, Jido.Agent.t()} | {:error, term()}
```

Each helper documents its return or raise behavior, optional inputs, payload
and envelope options, and validation timing. Live helpers also document
caller context, timeout, and propagated Server exits.

## Equal authoring formats

The current SDK retains neutral definitions with no ID or state. Complete
instances use explicit instance options. All forms converge on `Agent.new/1`
and `Agent.instantiate/2`; the new module constructor also exposes `new/2`.

| Form | Definition | Complete instance |
| --- | --- | --- |
| Direct map or keyword | `Agent.new(attrs)` | `Agent.instantiate(definition, opts)` |
| Agent module / Spark | `Counter.agent()` | `Counter.new(opts)` or `Agent.new(Counter, opts)` |
| Runtime Builder | `Builder.build(builder)` | `Builder.build(builder, opts)` |
| Codec document | `Codec.decode(document, registry)` | `Codec.decode(document, registry, opts)` |

Agent constructors and Builder `build` functions also have bang variants. Agent instance
options retain the current SDK's `id` and combined `state` contract.

```elixir
alias Jido.Agent.Builder

builder =
  Builder.new(module: MyApp.Counter, name: "counter")
  |> Builder.schema(MyApp.Counter.schema())
  |> Builder.metadata(%{owner: :support})
  |> Builder.plugin(MyApp.AuditPlugin, %{limit: 10})
  |> Builder.route("counter.increment", MyApp.Increment,
    defaults: %{amount: 1}, priority: 10)
  |> Builder.route("system.*", MyApp.HandleSystem)

{:ok, agent} = Builder.build(builder, id: "counter-1")
```

`Builder.new(Counter)` copies the module configuration for staged use. The
Builder preserves declaration order and its first recorded error. Final
construction uses the normal Agent validator. Direct route input accepts
Router structs, Router tuples, route maps, and `{path, target, options}`.

## Codec and trusted Registry

```elixir
{:ok, document, registry} = Jido.Agent.Codec.encode(agent)
json = JSON.encode!(document)

{:ok, decoded} =
  Jido.Agent.Codec.decode(JSON.decode!(json), registry,
    id: agent.id, state: agent.state)
```

The generated Registry is for temporary transport and tests. Durable authoring
documents use `Codec.encode(agent, registry)` with an application-owned
`Jido.Agent.Codec.Registry`. Its entries have stable string IDs and typed
values: `agent`, `action`, `flow`, `plugin`, `schema`, `route_match`, `atom`,
and static struct `value`. Read aliases point directly to canonical entries.

The document contains static Agent configuration, never instance state,
interface source metadata, or runtime handles. It is not a checkpoint. Decode
resolves code and schemas through the Registry; stored strings cannot create
atoms, derive module names, or construct functions. Tuples, maps, atoms, and
non-UTF-8 binaries use closed tagged records. Duplicate decoded map keys fail.
The decoder checks depth, node, collection, and string-size limits before
resolving Registry entries.

`Jido.Plugin.Codec` uses the same Registry and record format inside Agent
Codec. It serializes one current Plugin declaration as module and options;
Plugin state and runtime are excluded.

## Verification

The five Basic source fixtures now use Spark. Their original fifteen runtime
contract tests remain enabled. Five additional parity tests rebuild each
fixture through map, keyword, Builder, and JSON forms and compare generated
live calls with direct execution. Pure authoring tests cover compile failures,
helper packaging, Registry aliases, malformed documents, and construction
parity, including a Flow target.

All active example Agent declarations use Spark blocks. Workflow and LLM Signal
helpers delegate to explicit route interfaces while preserving their existing
return values and defaults. Targets without named input fields use `input`
options. Custom input preparation and dynamic Signal types remain ordinary
functions. The migration preserves schemas, Plugin order and config, and route
order. Inline route targets remain available through `route_action/1`.

Run:

```shell
mix test test/jido/agent/authoring_test.exs
mix test --include integration test/examples/01_basic
mix test
mix test --cover
mix quality
```

Ash's explicit interface naming and input mapping informed this design. The
nested route layout is Jido's choice. See [Ash code interfaces](https://ash.hexdocs.pm/code-interfaces.html).
Jido uses Spark directly and does not depend on Ash.
