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

An Agent module provides its neutral definition through `definition/0`:

```elixir
definition = MyApp.Counter.definition()
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
but they cannot replace it. The owning Agent Plugin contribution changes that
key.
See [Plugin-Owned State](plugin-state.md).

Jido also checks portability when it creates a checkpoint. State for durable
use must not contain PIDs, ports, references, functions, or other local runtime
values.

## Keep Identity Stable

An Agent ID identifies one logical instance in the current Jido instance and
partition APIs. A `Jido.Agent.Ref` gives the logical Agent one stable
`{namespace, partition, id}` identity value:

```elixir
ref =
  Jido.Agent.Ref.new!(
    namespace: "my-app/primary",
    partition: nil,
    id: agent.id
  )
```

The Ref does not contain the Agent module, PID, node, or a revision. A Jido
instance with a stable namespace can build and use it directly:

```elixir
{:ok, ref} = MyApp.Jido.agent_ref(agent.id, partition: "north")
{:ok, server} = MyApp.Jido.start_agent_ref(ref, MyApp.Counter)
{:ok, ^server} = MyApp.Jido.resolve_agent(ref)
```

Ref-first operations validate the full Ref and resolve the current local PID
for each operation. They do not route to another node. Current runtime
functions still accept IDs, PIDs, and existing partition values.

A state version identifies one committed revision. An activation ID identifies
one Agent Server lifetime. Do not use these values as substitutes for one
another.

Next, read [State Schemas](state-schemas.livemd) and
[Portable State And Checkpoints](portable-state-and-checkpoints.md).
