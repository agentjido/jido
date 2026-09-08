# Agent Definitions and Instances

Jido separates declaration from instantiation. You first declare a reusable
Agent definition. You then instantiate that definition as an immutable
`Jido.Agent` value. The value has two valid forms.

| Form | ID | State | Purpose |
| --- | --- | --- | --- |
| Definition | `nil` | `nil` | Reusable data schema, routes, Plugins, and metadata |
| Instance | Nonempty string | Complete map | One identified Agent with validated state |

A value with only an ID or only state is invalid.

## Declare A Definition

An Agent module provides its neutral definition through `agent/0`:

```elixir
definition = MyApp.Counter.agent()
true = Jido.Agent.definition?(definition)
```

You can also use `Jido.Agent.new/1`, `Jido.Agent.Builder`, or
`Jido.Agent.Codec`. All authoring forms use the same construction validation.

Keep the data schema static. Put changing values in instance state or command
input. A runtime closure is not portable authoring data.

## Instantiate An Agent

Use the module helper or instantiate a definition:

```elixir
{:ok, first} = MyApp.Counter.new(id: "counter-1")

{:ok, second} =
  Jido.Agent.instantiate(definition,
    id: "counter-2",
    state: %{count: 10}
  )
```

Instantiation applies data schema defaults and validates complete state. Do not
build an Agent struct by hand and assume it is valid.

## Own Complete State

The Agent owns all domain state. A successful Action or Flow returns the
complete next state map. Use `context.agent_state` as the base for updates so
you retain other domain fields.

A Plugin can own one declared state key. Agent executables can read that key,
but they cannot replace it. The Plugin update stage owns changes to that key.
See [Plugin-Owned State](plugin-state.md).

Jido also checks portability when it creates a checkpoint. State for durable
use must not contain PIDs, ports, references, functions, or other local runtime
values.

## Keep Identity Stable

An Agent ID identifies one logical instance inside a Jido instance and
partition. A state version identifies one committed revision. An activation ID
identifies one Agent Server lifetime. Do not use these values as substitutes
for one another.

Next, read [State Schemas](state-schemas.livemd) and
[Portable State And Checkpoints](portable-state-and-checkpoints.md).
