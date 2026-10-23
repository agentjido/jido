# Documents and Views

To store Agent definitions in a database, or show them in a UI, you need a
format that doesn't let stored data choose which modules your code runs.
`Jido.Authoring` encodes portable Agent definitions. The document refers to
modules, schemas, and data atoms only through a Registry you own.
`Jido.Agent.View` produces a read-only summary for a client.

```elixir
{:ok, json} = Jido.Authoring.encode_json(agent)
{:ok, definition} = Jido.Authoring.decode_json(json)

definition == Jido.Agent.definition(agent)
# => true

{:ok, view} = Jido.Agent.View.project(agent, registry)
view["operations"]["total"]
# => 2
```

This guide covers the Registry, export and import, what import rejects, and
Views. Read it after [Define an Agent](define-and-instantiate-an-agent.livemd).

The examples use this Agent:

```elixir
defmodule Doc.Add do
  use Jido.Action,
    name: "add",
    schema: Zoi.object(%{amount: Zoi.integer()}),
    output_schema: Zoi.map()

  @impl true
  def run(%{amount: amount}, %{agent_state: state}),
    do: {:ok, %{state | count: state.count + amount}}
end

defmodule Doc.Counter do
  use Jido.Agent, name: "counter", description: "Counts things"

  state do
    schema(Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}))
  end

  routes do
    signal_source("/guides/documents")

    route "counter.add", Doc.Add, as: :add, defaults: %{amount: 1} do
      state from: output()
    end

    route "counter.forward" do
      forward to: parent()
    end
  end
end
```

## The Trusted Registry

An Agent definition holds Action modules, Zoi schema structs, and atoms. None
of these survive JSON. Converting `"actions/add"` back to `Doc.Add` is a
security boundary: if the conversion trusts the document, whoever edits the
document controls which code runs.

A `Jido.Authoring.Registry` maps stable `{id, vsn}` keys to `{kind, value}`
pairs. Documents can only refer to those exact references.

```elixir
registry =
  Jido.Authoring.Registry.new!(%{
    {"agents/counter", 1} => {:agent, Doc.Counter},
    {"actions/add", 1} => {:action, Doc.Add},
    {"schemas/counter-state", 1} => {:schema, Doc.Counter.definition().schema},
    {"atoms/add", 1} => {:atom, :add},
    {"atoms/amount", 1} => {:atom, :amount}
  })

authoring_opts = [registry: registry, codec: Jido.Agent.Codec]
```

The Agent codec accepts `:agent`, `:action`, `:flow`, `:plugin`, `:extension`,
`:transform`, `:schema`, and `:atom`. Each typed value has one canonical
reference.

Register:

- the Agent module and every Action or Flow target;
- the state schema;
- every extension or Plugin provider module; and
- atoms used as data: `as:` helper names, keys in `defaults`, and keys in
  metadata, extension data, and topology data.

Jido already knows its structural names, such as `path`, `handler`, and
`kind`. Keep the Registry in code, review changes to it, and never build it
from stored data.

## Export

`Jido.Authoring.encode_json/2` encodes the definition of a source as a JSON
string. `Jido.Authoring.encode/2` returns the same document as a map. The source
can be a definition, an Agent module, or an instance. Discovery supplies the
Registry and codec by default. Use `authoring_opts` with a manually built
Registry.

```elixir
agent = Doc.Counter.instantiate!(id: "counter-1", state: %{count: 7})
{:ok, json} = Jido.Authoring.encode_json(agent, authoring_opts)
```

The document has `"type" => "jido.agent.definition"`, `"vsn" => 1`, and a
`"definition"` object. Module references look like this:

```json
{"id": "actions/add", "vsn": 1}
```

Maps are stored as entry lists, so atom and string keys stay distinct. The
document never contains Agent `id` or `state`. Module callbacks are not encoded.
An instance and its definition produce the same document.

Portable data can contain JSON scalar values, proper lists, maps, and atoms
that have `:atom` Registry entries. It cannot contain tuples, structs, live
values, or invalid UTF-8 strings.

If a value isn't registered, export fails:

```text
{:error, %Jido.Authoring.Error.InvalidError{code: :unknown_reference}}
```

The error doesn't say which value is missing. Compare the Agent's modules,
schema, and atom keys against the Registry.

## Import

`Jido.Authoring.decode_json/2` decodes through the same Registry. It then calls
`Jido.Agent.define/1` to validate the complete definition.

```elixir
{:ok, definition} = Jido.Authoring.decode_json(json, authoring_opts)

definition == Doc.Counter.definition()
# => true
```

Import returns a definition. It does not start a process, start Plugin
runtimes, restore state, or resume work. Instantiate the definition before you
start it.

## Import Failures

Import fails closed. Each case returns an error and no Agent:

| Problem | Error message |
| --- | --- |
| An ID not in the Registry | `:reference` Authoring issue |
| An ID with the wrong kind | `:reference` Authoring issue |
| An unknown document `type` or `vsn` | `:unsupported_document` Authoring issue |
| Malformed JSON | `:invalid_json` Authoring issue |
| Not a string, or larger than 8 MiB | `:invalid_json` Authoring issue |
| A well-formed document with an invalid Agent | The normal `Jido.Agent` validation error |

Replace `"actions/add"` with `"actions/delete_everything"` in the JSON and
import fails with a Registry reference issue. No module
lookup happens. Imported documents get the same validation as a DSL module:
fields, routes, extensions, and schema.

## Test Round Trips

Tests must also supply an explicit Registry:

```elixir
{:ok, document} = Jido.Authoring.encode(Doc.Counter.definition(), authoring_opts)

{:ok, decoded} =
  Jido.Authoring.decode(JSON.decode!(JSON.encode!(document)), authoring_opts)

decoded == Doc.Counter.definition()
# => true
```

There is no generated Registry for Agent documents. This keeps every written
ID under application control.

## Safe Views

`Jido.Agent.View.project/3` builds a read-only summary for dashboards, admin
APIs, and catalogs:

```elixir
{:ok, view} = Jido.Agent.View.project(agent, registry)
```

```elixir
%{
  "type" => "jido.agent.view",
  "vsn" => 1,
  "id" => "counter-1",
  "name" => "counter",
  "description" => "Counts things",
  "definition_vsn" => 1,
  "agent_type" => %{"id" => "agents/counter", "vsn" => 1},
  "schema" => %{"id" => "schemas/counter-state", "vsn" => 1},
  "operations" => %{
    "items" => [
      %{"signal_type" => "counter.add", "kind" => "action",
        "target" => %{"id" => "actions/add", "vsn" => 1}},
      %{"signal_type" => "counter.forward", "kind" => "forward",
        "target" => %{"kind" => "parent"}}
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
| Trusted Registry | Every exposed code value and schema needs an application-owned ID. |
| Bounded size | `operation_limit:` caps the route list. Default 100, maximum 500. When it cuts the list, `"total"` keeps the real count and `"truncated"` is `true`. |
| No process | `project/3` reads data. It never contacts an Agent process. |

## Which Format To Use

| Format | Contains | Use it for |
| --- | --- | --- |
| Agent definition document (`Jido.Authoring`) | Portable authoring data without ID or state | Storing and loading Agent definitions. |
| Agent View (`Jido.Agent.View`) | Public definition data and route summaries | Display and discovery. |
| Agent checkpoint | Portable identity and live state | Persistence and recovery. |

Checkpoints are covered in the Build Durable Systems guides.

## Next

- [Composition Vocabulary](composition-vocabulary.md) defines the terms for
  Agents built from Agents.
- [Mutations and Diffs](agent-mutations-and-diffs.livemd) changes a
  definition from inside a Turn.
