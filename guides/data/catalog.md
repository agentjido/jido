# Catalog and Discovery

This guide shows how to build a `Jido.Catalog`, look up its entries, limit what callers can see, and publish one Catalog for the whole application.

A Catalog maps stable IDs to trusted targets such as Action modules, Flow modules, atoms, and schemas. Stored documents hold those IDs, so a document never holds a module name. A Catalog is only an inventory. Finding an entry does not grant permission to run its target, so apply your own policy before you run it.

## Build a Catalog

`Jido.Catalog.from_targets!/3` is the shortest way to build one. It takes a provider module, an OTP application, and a map of `{id, vsn}` to `{kind, target}`.

```elixir
defmodule CatalogGuide.ChargeInvoice do
  use Jido.Action, id: "billing/charge-invoice", vsn: 2, name: "charge_invoice"

  @impl true
  def run(params, _context), do: {:ok, params}
end

catalog =
  Jido.Catalog.from_targets!(CatalogGuide.ChargeInvoice, :billing, %{
    {"billing/charge-invoice", 2} => {:action, CatalogGuide.ChargeInvoice},
    {"billing/atoms/paid", 1} => {:atom, :paid},
    {"billing/schemas/invoice", 1} =>
      {:schema, Jido.Joi.object(%{number: Jido.Joi.string()})}
  })
```

## Look up entries

Each lookup returns a `Jido.Catalog.Entry` or `nil`.

```elixir
alias Jido.Catalog

%{kind: :action, target: CatalogGuide.ChargeInvoice, application: :billing} =
  Catalog.get(catalog, "billing/charge-invoice", 2)

nil = Catalog.get(catalog, :flow, "billing/charge-invoice", 2)

%{id: "billing/atoms/paid"} = Catalog.get_by_target(catalog, :atom, :paid)

["billing/atoms/paid", "billing/charge-invoice", "billing/schemas/invoice"] =
  catalog |> Catalog.list() |> Enum.map(& &1.id)

["billing/atoms/paid"] = catalog |> Catalog.list(:atom) |> Enum.map(& &1.id)
```

`Jido.Catalog.list/1` returns entries in a fixed order, sorted by ID and version.

When your code needs a target or a reference and must handle failure, use `Jido.Catalog.resolve/3` and `Jido.Catalog.reference/3`. They check the kind and return a `Jido.Catalog.Error` that says what went wrong. Both accept one kind or a list of kinds.

```elixir
alias Jido.Catalog

{:ok, CatalogGuide.ChargeInvoice} = Catalog.resolve(catalog, {"billing/charge-invoice", 2}, :action)
{:ok, {"billing/charge-invoice", 2}} = Catalog.reference(catalog, [:flow, :action], CatalogGuide.ChargeInvoice)

{:error, %Jido.Catalog.Error{message: "Catalog reference has unsupported vsn", details: %{supported_vsns: [2]}}} =
  Catalog.resolve(catalog, {"billing/charge-invoice", 1}, :action)

{:error, %Jido.Catalog.Error{message: "unknown Catalog reference"}} =
  Catalog.resolve(catalog, {"billing/refund", 1}, :action)
```

For the JSON form of a reference, see [Portable Values](portable-values-and-references.md).

## Entry rules

`Jido.Catalog.Entry.new/1` validates these fields. `:name` and `:description` are optional text.

| Field | Rule |
| --- | --- |
| `:id` | 1 to 255 bytes. Starts with a letter or digit. Then letters, digits, and `. _ / : @ -` |
| `:vsn` | Positive integer |
| `:kind` | Any atom except `nil`, `true`, `false`, and `:alias` |
| `:target` | Depends on the kind |
| `:provider` | A module atom |
| `:application` | An application atom |

| Kind | Target rule |
| --- | --- |
| `:action`, `:flow` | A module atom |
| `:atom` | Any atom except `nil`, `true`, and `false` |
| `:schema` | A static Joi schema that accepts map-shaped data |
| Any other kind | Static data that passes `Jido.Joi.validate_static/1` |

```elixir
alias Jido.Catalog.Entry

base = %{id: "billing/tax-rule", vsn: 1, provider: CatalogGuide.ChargeInvoice, application: :billing}

{:ok, %Entry{kind: :tax_rule}} = Entry.new(Map.merge(base, %{kind: :tax_rule, target: %{rate: 7}}))

{:error, {:invalid_catalog_entry, :id, "tax rule"}} =
  Entry.new(Map.merge(base, %{id: "tax rule", kind: :tax_rule, target: %{rate: 7}}))

{:error, {:invalid_catalog_entry, :target, "runtime process values are not supported at [:owner]"}} =
  Entry.new(Map.merge(base, %{kind: :tax_rule, target: %{owner: self()}}))
```

`Jido.Catalog.new/1` also rejects conflicts and enforces a limit of 10,000 entries. One `{id, vsn}` pair can have one entry, and one `{kind, target}` pair can have one reference.

```elixir
{:error, {:catalog_conflict, :target, {:atom, :paid}, [{"a/paid", 1}, {"b/paid", 1}]}} =
  Jido.Catalog.from_targets(CatalogGuide.ChargeInvoice, :billing, %{
    {"a/paid", 1} => {:atom, :paid},
    {"b/paid", 1} => {:atom, :paid}
  })
```

## Compare Catalogs by revision

`Jido.Catalog.revision/1` returns a SHA-256 digest, Base64-encoded, of the sorted entries. Two Catalogs with the same entries have the same revision. Use it to detect a changed inventory within one system. Do not recompute it elsewhere, because it hashes Erlang terms.

## Contribute entries from a module

`Jido.Catalog.Manifest` is one validated contribution. It adds the provider and application to each entry and does not publish anything. `Jido.Catalog.new/1` takes entries and manifests together.

Any module can contribute by defining `__jido_catalog_manifest__/0`, which returns one map or a list of maps.

```elixir
defmodule CatalogGuide.Vocabulary do
  def __jido_catalog_manifest__ do
    [
      %{id: "billing/atoms/open", vsn: 1, kind: :atom, target: :open},
      %{id: "billing/atoms/void", vsn: 1, kind: :atom, target: :void}
    ]
  end
end

{:ok, manifest} =
  Jido.Catalog.Manifest.new(
    CatalogGuide.Vocabulary,
    :billing,
    CatalogGuide.Vocabulary.__jido_catalog_manifest__()
  )

{:ok, vocabulary} = Jido.Catalog.new([manifest])
%{provider: CatalogGuide.Vocabulary} = Jido.Catalog.get(vocabulary, "billing/atoms/void", 1)
```

`use Jido.Action`, `use Jido.Flow`, `use Jido.Agent`, and `use Jido.Plugin` generate this function for you. Give each module an explicit `id:` and `vsn:`. An Action's default ID contains its module name, such as `"Elixir.Billing.Charge"`, so renaming the module would break stored references.

Inline Actions stay out of the Catalog. They belong to their owner modules.

## Limit what a caller sees

`Jido.Catalog.View` filters a Catalog by kind, by target, or both. The result has the same lookups. It limits visibility and does not grant execution rights.

```elixir
alias Jido.Catalog.View

view = View.new!(catalog, kinds: [:action])

["billing/charge-invoice"] = view |> View.list() |> Enum.map(& &1.id)
nil = View.get(view, "billing/atoms/paid", 1)
%{vsn: 2} = View.get_by_target(view, :action, CatalogGuide.ChargeInvoice)

true = View.revision(view) == Jido.Catalog.revision(catalog)
```

`Jido.Catalog.View.revision/1` returns the revision of the source Catalog, so it does not change with the filter.

## Publish one application Catalog

`Jido.Catalog.Discovery` builds a Catalog and a codec index, and publishes both as one atomic value. Jido starts one scan of all loaded applications when it starts. The scan runs in the background and takes a moment, so check `Jido.Catalog.Discovery.ready?/0` before you depend on it. Until the first build finishes, `Jido.Catalog.Discovery.catalog/0` raises `Jido.Codec.Error.InternalError` with the code `:catalog_not_initialized`.

```elixir
alias Jido.Catalog.Discovery

true =
  Enum.find_value(1..200, fn _attempt ->
    Process.sleep(50)
    Discovery.ready?()
  end)

%{kind: :schema} = Discovery.get("jido/schemas/map", 1)
true = Jido.Plugin.Scheduler in Discovery.included_plugins()
true = Discovery.list(:plugin) != []
```

The Catalog always holds the `"jido/schemas/map"` schema entry. `Jido.Catalog.Discovery.included_plugins/0` lists the first-party Plugin modules in this release.

### Restrict the scan

When your application accepts stored definitions from users, replace the default scan of all loaded applications with an allowlist.

<!-- partial -->
```elixir
config :jido, Jido.Catalog.Discovery,
  applications: [:my_app, :jido],
  modules: [MyApp.SpecialAction]
```

`:applications` defaults to `:loaded`. `:modules` adds individual modules.

### Refresh the Catalog

`Jido.Catalog.Discovery.refresh/1` rebuilds everything and replaces the published value in one step. Call it after loading an application late. Its `:applications` option overrides the configured list. Its `:modules` option adds to the configured modules.

A source in `:modules` is a module that belongs to a loaded application, or a `{module, application}` tuple.

```elixir
alias Jido.Catalog.Discovery

:ok =
  Discovery.refresh(
    applications: [],
    modules: [
      {CatalogGuide.ChargeInvoice, :billing},
      {CatalogGuide.Vocabulary, :billing}
    ]
  )

["billing/atoms/open", "billing/atoms/void", "billing/charge-invoice", "jido/schemas/map"] =
  Enum.map(Discovery.list(), & &1.id)

%{vsn: 2} = Discovery.get_by_target(:action, CatalogGuide.ChargeInvoice)

{:error, {:application_not_loaded, :unknown_app}} = Discovery.refresh(applications: [:unknown_app])
"billing/atoms/void" = Discovery.get("billing/atoms/void", 1).id
```

The last two lines show that a failed refresh returns an error and keeps the last published value. Wait for `Jido.Catalog.Discovery.ready?/0` before your first refresh, because the first scan publishes when it finishes and would replace your result.

If the first scan itself fails, Jido logs a warning, and later reads raise with the code `:catalog_initialization_failed`. A later successful refresh replaces that state.

A refresh scans modules and replaces a `:persistent_term` value. Run it when deployment or configuration changes, not on each request.

## Related

- [Jido.Codec Documents](versioned-documents.md) routes documents through the published index.
- [Store Flows as JSON](../flow-data/flow-storage.md) lists the Catalog entries that a Flow document needs.
- [Security Model](../operations/security.md) covers authorization around these lookups.
