# Documents and Views

This guide shows how to store an Agent definition as a versioned JSON document and how to publish a safe view of one. Both use a `Jido.Catalog` to replace modules with stable IDs.

Use a document to save and reload a definition. Use a view to show an Agent to a UI, an API client, or another service.

## Build a Catalog

A Catalog lists the trusted values a document can refer to. Encoding fails for a value with no entry. The target Agent here has an Action route, a schema, an atom helper name, and an atom key in its route defaults.

```elixir
defmodule DocumentGuide.AssignTicket do
  use Jido.Action,
    name: "document_guide_assign_ticket",
    schema: Jido.Joi.object(%{queue: Jido.Joi.string()})

  @impl Jido.Action
  def run(%{queue: queue}, %{agent_state: state}), do: {:ok, %{state | queue: queue}}
end

defmodule DocumentGuide.TicketAgent do
  use Jido.Agent,
    name: "ticket",
    description: "Assigns support tickets",
    vsn: 2

  state do
    schema Jido.Joi.object(%{queue: Jido.Joi.string() |> Jido.Joi.default("inbox")})
  end

  routes do
    signal_source "/support/ticket"

    route "ticket.assign", DocumentGuide.AssignTicket, as: :assign, defaults: %{queue: "general"}
  end
end

catalog =
  Jido.Catalog.from_targets!(DocumentGuide, :jido, %{
    {"agents/ticket", 1} => DocumentGuide.TicketAgent,
    {"schemas/ticket", 1} => DocumentGuide.TicketAgent.definition().schema,
    {"actions/assign-ticket", 1} => DocumentGuide.AssignTicket,
    {"atoms/assign", 1} => :assign,
    {"atoms/queue", 1} => :queue
  })

%Jido.Catalog{} = catalog
```

Each key is `{id, vsn}`, and each value is the registered target. See [Catalog and Discovery](../data/catalog.md).

## Encode a definition

`Jido.Codec.encode/2` writes a JSON-safe Map. Pass `codec: Jido.Agent.Codec` and the Catalog as `:catalog`.

```elixir
{:ok, document} =
  Jido.Codec.encode(DocumentGuide.TicketAgent.definition(), catalog: catalog, codec: Jido.Agent.Codec)

%{"type" => "jido.agent.definition", "vsn" => 1, "definition" => fields} = document

%{"id" => "actions/assign-ticket", "vsn" => 1} =
  hd(fields["routes"])["handler"]["target"]

%{"id" => "agents/ticket", "vsn" => 1} = fields["module"]
```

`Jido.Codec.encode_json/2` returns a JSON string instead. The default size limit is 8 MiB. Set another with `:maximum_json_bytes`.

A document stores the definition only. Encoding an instance drops its `id` and `state`, so use [persistence](../durability/checkpoints-and-data-upgrades.md) to save running data.

```elixir
ticket = DocumentGuide.TicketAgent.instantiate!(id: "ticket-1", state: %{queue: "billing"})

{:ok, from_instance} = Jido.Codec.encode(ticket, catalog: catalog, codec: Jido.Agent.Codec)
true = from_instance == document
```

## Decode a definition

`Jido.Codec.decode_json/2` and `Jido.Codec.decode/2` rebuild the definition with the Catalog and validate it through `Jido.Agent.define/1`. The result equals the original, and it starts no process.

```elixir
{:ok, json} =
  Jido.Codec.encode_json(DocumentGuide.TicketAgent.definition(), catalog: catalog, codec: Jido.Agent.Codec)

{:ok, restored} = Jido.Codec.decode_json(json, catalog: catalog, codec: Jido.Agent.Codec)

true = restored == DocumentGuide.TicketAgent.definition()

{:ok, assigned, []} =
  restored
  |> Jido.Agent.instantiate!(id: "ticket-2")
  |> Jido.Agent.cmd(DocumentGuide.TicketAgent.assign_signal!())

"general" = assigned.state.queue
```

Decoding resolves only entries in the Catalog you pass, so the Catalog decides which code a document can reach. A Catalog entry is inventory and does not authorize a target. Apply your own policy before you load a document from outside your system.

## Know what must be in the Catalog

| Definition part | Registered value |
| --- | --- |
| `module`, when set | Agent module |
| The state schema | Joi schema |
| An Action or Flow route target | Action or Flow module |
| A transform target | `{module, function, 1}` tuple |
| A Plugin provider | Plugin module |
| An atom in data, such as a helper name or Map key | Atom value |

The Agent reader checks these values for each field. A module that cannot load
returns an error during decoding.

A missing entry returns a `Jido.Codec.Error.InvalidError`.

```elixir
partial = Jido.Catalog.from_targets!(DocumentGuide, :jido, %{})

{:error, %Jido.Codec.Error.InvalidError{code: :unknown_reference}} =
  Jido.Codec.encode(DocumentGuide.TicketAgent.definition(), catalog: partial, codec: Jido.Agent.Codec)
```

A route with an inline Action can also be encoded, when the target from `route_executable!/1` is in the Catalog. That target is a generated module, so a named Action module is the better choice for a stored definition.

## Project a view

`Jido.Agent.View.project/3` builds a plain JSON Map from a module, a definition, or an instance. All three give the same shape, and only an instance has an `"id"`. It never contacts a process.

```elixir
{:ok, view} = Jido.Agent.View.project(DocumentGuide.TicketAgent, catalog)

%{
  "type" => "jido.agent.view",
  "vsn" => 1,
  "id" => nil,
  "name" => "ticket",
  "description" => "Assigns support tickets",
  "definition_vsn" => 2,
  "agent_type" => %{"id" => "agents/ticket", "vsn" => 1},
  "schema" => %{"id" => "schemas/ticket", "vsn" => 1},
  "operations" => %{
    "total" => 1,
    "truncated" => false,
    "items" => [
      %{
        "path" => "ticket.assign",
        "as" => %{"$type" => "atom", "id" => "atoms/assign", "vsn" => 1},
        "handler" => %{"kind" => "action", "target" => %{"id" => "actions/assign-ticket", "vsn" => 1}},
        "state" => %{"source" => "output", "path" => []},
        "reply" => nil
      }
    ]
  }
} = view

{:ok, instance_view} = Jido.Agent.View.project(ticket, catalog)
"ticket-1" = instance_view["id"]
true = %{instance_view | "id" => nil} == view
```

A view leaves out Agent state, `metadata`, Plugin options, route defaults, and route match functions. Schema, targets, and helper names appear only as Catalog references. It does not expose a module name.

Limit the route list with `:operation_limit`, from 0 to 500. The default is 100. `total` keeps the full count, and `truncated` reports the cut.

```elixir
{:ok, short} = Jido.Agent.View.project(ticket, catalog, operation_limit: 0)
%{"items" => [], "total" => 1, "truncated" => true} = short["operations"]

{:error, %Jido.Error.ValidationError{}} = Jido.Agent.View.project(ticket, catalog, operation_limit: 501)
```

## Related

- [Jido.Codec Documents](../data/versioned-documents.md) covers the document contract and limits.
- [Portable Values](../data/portable-values-and-references.md) covers how atoms and Maps are encoded.
- [Checkpoints and Upgrades](../durability/checkpoints-and-data-upgrades.md) covers saved instances.
