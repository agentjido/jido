# Flow Identity

A Flow's identity is a deterministic hash of its meaning. This guide explains what the hash covers and what it does not, and how it relates to the version numbers in Jido.
Use it to answer one question: is this stored Flow still the definition I reviewed?

## Read an identity

`Jido.Flow.semantic_identity/1` validates a Flow and returns its identity. It uses a SHA-256 digest and a UUIDv8 derived from the same hash.

```elixir
defmodule RefundIdentity.Issue do
  use Jido.Action, id: "refunds/issue", vsn: 1, name: "issue_refund"

  @impl true
  def run(%{amount_cents: amount_cents}, _context), do: {:ok, %{refunded_cents: amount_cents}}
end

defmodule RefundIdentity.Definition do
  alias Jido.Flow.Ref

  def attrs do
    %{
      name: "issue_refund",
      components: [
        %{
          kind: :step,
          name: "issue",
          action: RefundIdentity.Issue,
          params: %{amount_cents: Ref.input(:amount_cents)}
        }
      ],
      output: Ref.result("issue")
    }
  end

  def digest(attrs) do
    {:ok, identity} = attrs |> Jido.Flow.new!() |> Jido.Flow.semantic_identity()
    identity.digest
  end
end

{:ok, identity} =
  RefundIdentity.Definition.attrs() |> Jido.Flow.new!() |> Jido.Flow.semantic_identity()

%{version: 1, algorithm: :sha256, digest: digest, uuid: uuid} = identity
64 = byte_size(digest)
36 = byte_size(uuid)
```

This Flow has this identity:

```text
%{
  version: 1,
  algorithm: :sha256,
  digest: "bfa214ad4f34988eb17dfdc40525ebbb0895059156a65b2f43bfb36212c474e7",
  uuid: "bfa214ad-4f34-888e-b17d-fdc40525ebbb"
}
```

## What changes the identity

Equal definitions have equal identities, however you author them. A DSL module, a data definition, and a decoded JSON document can all produce one identity.

```elixir
defmodule RefundIdentity.FromDsl do
  use Jido.Flow, name: "issue_refund"

  flow do
    step "issue", action: RefundIdentity.Issue, params: %{amount_cents: input(:amount_cents)}
    output result("issue")
  end
end

catalog =
  Jido.Catalog.from_targets!(RefundIdentity.Definition, :refunds, %{
    {"refunds/issue", 1} => {:action, RefundIdentity.Issue},
    {"refunds/atoms/amount_cents", 1} => {:atom, :amount_cents}
  })

options = [catalog: catalog, codec: Jido.Flow.Codec]
from_data = Jido.Flow.new!(RefundIdentity.Definition.attrs())

{:ok, json} = Jido.Codec.encode_json(from_data, options)
{:ok, from_json} = Jido.Codec.decode_json(json, options)

{:ok, expected} = Jido.Flow.semantic_identity(from_data)
{:ok, ^expected} = Jido.Flow.semantic_identity(from_json)
{:ok, ^expected} = Jido.Flow.semantic_identity(RefundIdentity.FromDsl.flow())
```

The hash covers the Flow's `name`, `schema`, `output_schema`, `output`, and components. For each component, it covers everything except `meta`.

| Change | Identity changes? |
| --- | --- |
| A literal in `params` | Yes |
| The Flow `name` | Yes |
| The `schema` or `output_schema` | Yes |
| The `output` expression | Yes |
| The target module, including a rename | Yes |
| A component added, removed, or renamed | Yes |
| The members of `needs` | Yes |
| The `description` | No |
| Component `meta` | No |
| The order of the `components` list | No |
| The order inside `needs` | No |
| A Catalog ID or version for the same target | No |
| Run input or context | No |

This code proves the main rows:

```elixir
attrs = RefundIdentity.Definition.attrs()
digest = &RefundIdentity.Definition.digest/1
base = digest.(attrs)

^base = digest.(Map.put(attrs, :description, "Issue a customer refund"))

^base =
  digest.(update_in(attrs.components, fn [issue] -> [Map.put(issue, :meta, %{team: "support"})] end))

renamed = digest.(Map.put(attrs, :name, "issue_refund_v2"))
true = renamed != base

changed_params =
  digest.(update_in(attrs.components, fn [issue] -> [%{issue | params: %{amount_cents: 500}}] end))

true = changed_params != base
```

A reference and a literal map with the same fields have different identities, because the `Jido.Flow.Ref` struct tag is part of the hashed term.

## What identity does not cover

Identity describes the graph. It does not identify deployed code.

- **Action code.** The hash holds the target module name, not its BEAM file. Editing a `run/2` function, including an inline Step body, keeps the identity. Deploy an owning module with its generated Action modules.
- **Subflow contents.** A `:subflow` component contributes its target module name. A change inside that Flow module does not change the parent's identity.
- **Display text.** `description` and `meta` can change without a new identity, so do not use the digest to detect those edits.

The digest hashes Erlang terms, including module atoms and Joi schema values. Store it to compare definitions in one system. Do not treat it as a format that other languages can recompute.

## Detect a changed definition

Save the digest beside the document when you review it. Compare it after each load.

```elixir
catalog =
  Jido.Catalog.from_targets!(RefundIdentity.Definition, :refunds, %{
    {"refunds/issue", 1} => {:action, RefundIdentity.Issue},
    {"refunds/atoms/amount_cents", 1} => {:atom, :amount_cents}
  })

options = [catalog: catalog, codec: Jido.Flow.Codec]
approved = Jido.Flow.new!(RefundIdentity.Definition.attrs())

{:ok, json} = Jido.Codec.encode_json(approved, options)
{:ok, %{digest: approved_digest}} = Jido.Flow.semantic_identity(approved)

{:ok, loaded} = Jido.Codec.decode_json(json, options)
{:ok, %{digest: ^approved_digest}} = Jido.Flow.semantic_identity(loaded)

edited_json = String.replace(json, "issue_refund", "issue_any_refund")
{:ok, edited} = Jido.Codec.decode_json(edited_json, options)
{:ok, %{digest: edited_digest}} = Jido.Flow.semantic_identity(edited)
true = edited_digest != approved_digest
```

## Version numbers

Jido has several version numbers, and each one answers a different question. A data-defined Flow has no revision number of its own, so store a revision beside the document if your application needs one.

| Number | Where it appears | What it versions |
| --- | --- | --- |
| Identity `version` | `Jido.Flow.semantic_identity/1` | The hash format. Currently `1`. |
| Explanation `version` | `Jido.Flow.explain/1` | The inspection map format. Currently `1`. |
| Document `vsn` | The stored JSON root | The stored Flow format. Currently `2`. |
| Catalog `vsn` | Each `{"id": ..., "vsn": ...}` reference | One registered target. |
| Module `vsn:` | `use Jido.Action` and `use Jido.Flow` | The module's published Catalog version. Defaults to `1`. |

A Flow module's `id:` defaults to its module name, such as `"Elixir.MyApp.Refunds"`. Set an explicit `id:` for any module that a stored document references, so that renaming the module does not break those documents. A module's `id:` and `vsn:` are not part of the Flow identity.

## Change an Action behind stored documents

Stored documents pin each target to a Catalog ID and version. To change an Action's behavior without changing old documents, add a new module under the next version and keep both in the Catalog.

```elixir
defmodule RefundIdentity.IssueV2 do
  use Jido.Action, id: "refunds/issue", vsn: 2, name: "issue_refund_v2"

  @impl true
  def run(%{amount_cents: amount_cents}, _context) do
    {:ok, %{refunded_cents: amount_cents, review_required: amount_cents > 10_000}}
  end
end

catalog =
  Jido.Catalog.from_targets!(RefundIdentity.Definition, :refunds, %{
    {"refunds/issue", 1} => {:action, RefundIdentity.Issue},
    {"refunds/issue", 2} => {:action, RefundIdentity.IssueV2},
    {"refunds/atoms/amount_cents", 1} => {:atom, :amount_cents}
  })

options = [catalog: catalog, codec: Jido.Flow.Codec]
old_flow = Jido.Flow.new!(RefundIdentity.Definition.attrs())

new_flow =
  Jido.Flow.new!(
    update_in(RefundIdentity.Definition.attrs().components, fn [issue] ->
      [%{issue | action: RefundIdentity.IssueV2}]
    end)
  )

{:ok, old_json} = Jido.Codec.encode_json(old_flow, options)
{:ok, ^old_flow} = Jido.Codec.decode_json(old_json, options)
{:ok, %{refunded_cents: 100}} = Jido.Exec.run(old_flow, %{amount_cents: 100})

{:ok, %{review_required: false}} = Jido.Exec.run(new_flow, %{amount_cents: 100})

{:ok, %{digest: old_digest}} = Jido.Flow.semantic_identity(old_flow)
{:ok, %{digest: new_digest}} = Jido.Flow.semantic_identity(new_flow)
true = old_digest != new_digest
```

Remove the old entry only after you migrate its documents. A document that references a removed version fails to decode with an Issue, and `details.supported_vsns` lists the versions that remain.

```elixir
current_catalog =
  Jido.Catalog.from_targets!(RefundIdentity.Definition, :refunds, %{
    {"refunds/issue", 2} => {:action, RefundIdentity.IssueV2},
    {"refunds/atoms/amount_cents", 1} => {:atom, :amount_cents}
  })

full_catalog =
  Jido.Catalog.from_targets!(RefundIdentity.Definition, :refunds, %{
    {"refunds/issue", 1} => {:action, RefundIdentity.Issue},
    {"refunds/atoms/amount_cents", 1} => {:atom, :amount_cents}
  })

{:ok, old_json} =
  Jido.Codec.encode_json(Jido.Flow.new!(RefundIdentity.Definition.attrs()), catalog: full_catalog)

{:error, [issue]} =
  Jido.Codec.decode_json(old_json, catalog: current_catalog, codec: Jido.Flow.Codec)

["components", 0, "call", "target", "vsn"] = issue.path
%{supported_vsns: [2]} = issue.details
```

## Related

- [Store Flows as JSON](flow-storage.md) covers the Catalog and document format.
- [Inspect Flows](flow-inspection.md) reads identity with the rest of a Flow's data.
