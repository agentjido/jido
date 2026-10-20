# Documents and Views

To store Agent definitions in a database, or show them in a UI, you need a
format that doesn't let stored data choose which modules your code runs.
`Jido.Agent.Codec` encodes Agents as JSON documents that refer to modules and
atoms only through a Registry you own. `Jido.Agent.View` produces a read-only
summary that is safe to hand to a client.

```elixir
{:ok, json} = Jido.Agent.to_json(agent, registry)
{:ok, ^agent} = Jido.Agent.from_json(json, registry)

{:ok, view} = Jido.Agent.View.project(agent, registry)
view["operations"]["total"]
# => 2
```

This guide covers the Registry, export and import, what import rejects, and
Views. Read it after [Define an Agent](define-and-instantiate-an-agent.livemd).

The examples use this Agent:

```elixir
defmodule Doc.Add do
  use Jido.Action, name: "add", schema: Zoi.object(%{amount: Zoi.integer()})

  @impl true
  def run(%{amount: amount}, %{agent_state: state}),
    do: {:ok, %{state | count: state.count + amount}}
end

defmodule Doc.Counter do
  use Jido.Agent, name: "counter", description: "Counts things"

  agent do
    schema(Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}))
  end

  routes do
    signal_source("/guides/documents")
    route "counter.add", Doc.Add, as: :add, defaults: %{amount: 1}, emits: []
    route "counter.echo", emits: ["counter.echo"]
  end
end
```

## The Trusted Registry

An Agent definition holds Action modules, Zoi schema structs, and atoms. None
of these survive JSON. Converting `"actions/add"` back to `Doc.Add` is a
security boundary: if the conversion trusts the document, whoever edits the
document controls which code runs.

A `Jido.Codec.Registry` maps stable string IDs to `{kind, value}` pairs.
Documents can only refer to those IDs.

```elixir
registry =
  Jido.Codec.Registry.new!(%{
    "agents/counter" => {:agent, Doc.Counter},
    "actions/add" => {:action, Doc.Add},
    "schemas/counter-state" => {:schema, Doc.Counter.definition().schema},
    "atoms/add" => {:atom, :add},
    "atoms/amount" => {:atom, :amount}
  })
```

Kinds are `:agent`, `:action`, `:flow`, `:plugin`, `:schema`, `:atom`,
`:value`, `:extension`, `:transform`, and `:route_match`. Each value can have
only one ID.

Register:

- the Agent module and every Action or Flow target;
- the state schema;
- every Plugin module; and
- atoms used as data: `as:` helper names, keys in `defaults`, and keys in
  state.

Jido already knows its structural names, such as `path`, `handler`, and
`kind`. Keep the Registry in code, review changes to it, and never build it
from stored data.

## Export

`Jido.Agent.to_json/2` encodes a definition or an instance as a JSON string.
`Jido.Agent.Codec.encode/2` returns the same document as a map.

```elixir
agent = Doc.Counter.instantiate!(id: "counter-1", state: %{count: 7})
{:ok, json} = Jido.Agent.to_json(agent, registry)
```

The document has `"type" => "jido.agent"`, `"version" => 1`, and an `"agent"`
object with every Agent field. Module references look like this:

```json
{"$type": "reference", "kind": "action", "id": "actions/add"}
```

Maps are stored as entry lists, so atom and string keys stay distinct. An
instance document includes `id` and `state`. A definition document has
`null` for both.

If a value isn't registered, export fails:

```text
{:error, %Jido.Agent.Error{code: :unknown_reference,
                           message: "Registry has no identifier for Agent data"}}
```

The error doesn't say which value is missing. Compare the Agent's modules,
schema, and atom keys against the Registry.

## Import

`Jido.Agent.from_json/2` decodes through the same Registry, then runs full
Agent validation.

```elixir
{:ok, restored} = Jido.Agent.from_json(json, registry)

{restored == agent, restored.state}
# => {true, %{count: 7}}
```

The round trip is exact. Import returns a value: it doesn't start a process,
start Plugin runtimes, or resume work. Pass the value to `Jido.start_agent/2`
to run it.

## Import Failures

Import fails closed. Each case returns an error and no Agent:

| Problem | Error message |
| --- | --- |
| An ID not in the Registry, or with the wrong kind | `"Unknown or mismatched Registry identifier"` |
| An unknown document `type` or `version` | `"Unknown Agent document type or version"` |
| Malformed JSON | `"Invalid Agent JSON"` |
| Not a string, or larger than 8 MiB | `"Expected a JSON string of at most 8 MiB"` |
| A well-formed document with an invalid Agent | The normal `Jido.Agent` validation error |

Replace `"actions/add"` with `"actions/delete_everything"` in the JSON and
import fails with `"Unknown or mismatched Registry identifier"`. No module
lookup happens. Imported documents get the same validation as a DSL module:
fields, routes, Plugins, schema, and complete state.

## Test Round Trips

In tests, `Jido.Agent.Codec.encode/1` derives a temporary Registry:

```elixir
{:ok, document, temporary} = Jido.Agent.Codec.encode(Doc.Counter.definition())
{:ok, decoded} = Jido.Agent.Codec.decode(JSON.decode!(JSON.encode!(document)), temporary)

decoded == Doc.Counter.definition()
# => true
```

Derived IDs such as `"agent/0"` and `"action/2"` depend on traversal order and
change when your code changes. Use the temporary Registry to check that a
definition encodes. Don't store documents made with it.

## Safe Views

`Jido.Agent.View.project/3` builds a read-only summary for dashboards, admin
APIs, and catalogs:

```elixir
{:ok, view} = Jido.Agent.View.project(agent, registry)
```

```elixir
%{
  "type" => "jido.agent.view",
  "version" => 1,
  "id" => "counter-1",
  "name" => "counter",
  "description" => "Counts things",
  "definition_vsn" => 1,
  "agent_type_id" => "agents/counter",
  "schema_id" => "schemas/counter-state",
  "operations" => %{
    "items" => [
      %{"signal_type" => "counter.add", "kind" => "action",
        "target_id" => "actions/add", "emits" => []},
      %{"signal_type" => "counter.echo", "kind" => "pass_through",
        "target_id" => nil, "emits" => ["counter.echo"]}
    ],
    "total" => 2,
    "truncated" => false
  }
}
```

A View never contains Agent state, metadata, schema values, Plugin options,
or route defaults. Modules appear only as Registry IDs. A module, a
definition, and an instance all produce the same shape; `"id"` is `nil` for
the first two.

| Rule | Detail |
| --- | --- |
| Stable Registry | A temporary Registry fails with `"This operation requires a stable Registry"`. |
| Bounded size | `operation_limit:` caps the route list. Default 100, maximum 500. When it cuts the list, `"total"` keeps the real count and `"truncated"` is `true`. |
| No process | `project/3` reads data. It never contacts an Agent process. |

## Which Format To Use

| Format | Contains | Use it for |
| --- | --- | --- |
| Agent document (`Jido.Agent.Codec`) | A complete definition or instance | Storing and loading Agents. |
| Agent View (`Jido.Agent.View`) | Public definition data and route summaries | Display and discovery. |
| Plugin document (`Jido.Plugin.Codec`) | One Plugin and its options | Storing a Plugin declaration. |
| Agent checkpoint | Portable identity and live state | Persistence and recovery. |

Checkpoints are covered in the Build Durable Systems guides.

## Next

- [Composition Vocabulary](composition-vocabulary.md) defines the terms for
  Agents built from Agents.
- [Mutations and Diffs](agent-mutations-and-diffs.livemd) changes a
  definition from inside a Turn.
