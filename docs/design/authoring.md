> Deferred design proposal. This document is pending approval. It does not define
> the current core API. See [the current core scope](../../guides/core-scope.md).

# Agent authoring

[Design overview](README.md) | Related: [Agent](agent.md), [Plugins](plugins.md)

- Status: Historical module-only proposal; deferred
- Scope: Current authoring status and the earlier module-only design.

## Implementation status

The current SDK implements Spark block authoring, route-defined command and
Signal helpers, a runtime Builder, and Agent/Plugin Codecs. See
[Agent Spark DSL and authoring formats](agent-dsl-interfaces.md) for the current
contract. The module-only restrictions below describe the earlier proposal;
they do not describe the implemented authoring formats. The complete v3
versioned-module and state migration remains separate work.

## Historical module-only proposal

The sections below describe an earlier alternative. They are not removal
instructions for the current spike. This refinement retains DSL, Builder,
Codec, neutral definitions, and generated route helpers. The public
[Agent guide](../../guides/agents.md) describes construction today.

The earlier proposal would give Jido core one Agent authoring path:

```text
versioned Agent module
  -> private normalized static configuration
  -> Jido.Agent.new/2 with instance options
  -> complete %Jido.Agent{}
```

Core supplies the `use Jido.Agent` module DSL and constructors. Core does not
supply a runtime Builder, an Agent Codec, a Plugin Codec, or an authoring
Registry. These tools do not participate in Turn execution, commit, restore,
or runtime ownership. A separate authoring package can add them when a real
consumer needs them.

## Module contract

Every Agent is owned by one Agent module. The module declares all static
configuration and a positive definition revision:

```elixir
defmodule MyApp.SupportAgent do
  use Jido.Agent,
    definition_revision: 1,
    name: "support",
    description: "Owns support state and request handling",
    schema:
      Zoi.object(%{
        open_tickets: Zoi.integer() |> Zoi.default(0)
      }),
    metadata: %{owner: :support},
    plugins: [
      MyApp.SearchPlugin.new!(
        id: :search,
        options: %{limit: 10}
      )
    ],
    routes: [
      {"support.ticket.created", MyApp.OpenTicket,
       params: %{source: "agent"}, priority: 10}
    ]
end
```

The module macro validates and normalizes this configuration at compile time.
It stores the private result behind `__agent_config__/0`. This function is
framework metadata. It is not a second Agent value or a public authoring data
type.

The normalized fields are:

| Field | Rule |
| --- | --- |
| `module` | The module that owns the definition. |
| `definition_revision` | Required positive integer. |
| `name` | Required nonempty string. |
| `description` | Optional string. |
| `schema` | Static Zoi domain-state schema. |
| `metadata` | Static Map. |
| `plugins` | Ordered validated Plugin list. |
| `routes` | Ordered normalized route list. |

Unknown fields fail compilation. Declaration order is part of the normalized
definition. The module must increase `definition_revision` when any normalized
field changes.

## Construction

The public constructors accept only an Agent module and instance options:

```elixir
Jido.Agent.new(MyApp.SupportAgent,
  id: "support-1",
  state: %{open_tickets: 0}
)

Jido.Agent.new!(MyApp.SupportAgent,
  id: "support-1",
  state: %{open_tickets: 0}
)
```

The generated module API delegates to the same functions:

```elixir
MyApp.SupportAgent.new(opts \\ [])
MyApp.SupportAgent.new!(opts \\ [])
MyApp.SupportAgent.cmd(agent, signal, opts \\ [])
```

Instance options contain only Agent ID, initial domain state, and initial
Plugin state. They cannot replace the schema, routes, Plugins, metadata, name,
description, module, or definition revision.

Every successful constructor returns one complete `%Jido.Agent{}`. Core does
not expose a neutral Agent definition, a staged partial Agent, or a complete
Agent Map constructor.

## Persistence and restore

Every core Agent definition is module-owned and versioned. Persistent creation
also checks that the complete Agent static configuration equals the current
normalized module configuration. Restore requires the saved module and exact
definition revision before it validates saved state.

The checkpoint stores instance state. It is not an authoring document. Core has
no API that serializes or loads executable Agent configuration from a Map or
external document.

An external authoring package can define a trusted document format, editor, or
Builder. It must resolve its output to a versioned Agent module and call the
normal core constructor. It cannot create a second persistent definition
authority or bypass the exact module and revision checks.

## Startup and domain helpers

Use the Jido instance API to start an Agent. Do not generate a startup function
on each Agent module or repeat a wrapper that only inserts the module and ID.
See [startup and link ownership](jido-instance.md#startup-and-link-ownership).
Special operations such as required restoration can retain explicit functions.

Keep explicit domain helpers where they give a useful application API. For
example, `Counter.increment_signal/1` constructs a Signal for direct or live
execution, and `Counter.increment/3` sends it through the Server API. Such
helpers preserve public result and error tuples. They can pass Server timeout
and transient context options without adding execution policy.

Routes do not generate command functions. This decision resolves the repeated
helper review without a new macro or command DSL.

## Named-function targets: separate follow-up

The current shared executable contract accepts Actions and Flows. Portable
named-function targets remain a separate `jido_action` change tracked in issue
#4. Implement them at the common resolver and execution boundary so Agent routes
and Flow steps use one validation, result, error, and telemetry contract.

A future target needs explicit module, function, portable bound arguments, and
input/context semantics. It must preserve Zoi validation where required. Compare
it with the existing Action in one Basic route and remove one-use normalization
and summary modules in Sequential Data Flow before claiming a reduction in
application code. The current typed Basic Actions remain supported.

## Downstream composition

A downstream abstraction, such as an Agent package, refers to an Agent module.
It does not copy or overlay Agent schema, route, or Plugin declarations. This
keeps one owner for Agent behavior and one definition revision.

```elixir
defmodule MyApp.SupportAgent do
  use Jido.Agent,
    agent: MyApp.SupportAgent,
    model: :capable,
    instructions: "Resolve support requests."
end
```

`Jido.Agent` is outside Jido core. The example defines only the composition
rule.

## Proposed tests for the historical alternative

- The module macro rejects invalid or unknown static fields.
- Every Agent module requires a positive definition revision.
- Generated constructors and `Jido.Agent.new/2` return equal Agents for equal
  instance options.
- Instance options cannot replace static module configuration.
- Declaration order is stable.
- Construction applies domain and Plugin state defaults.
- Construction enforces the portable-state contract.
- Persistence rejects an Agent whose static configuration differs from its
  module definition.
- Restore rejects a missing module or changed definition revision.
- Core exposes no Builder, Agent Codec, Plugin Codec, authoring Registry,
  complete-Agent Map constructor, or public neutral Agent definition.
