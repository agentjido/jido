# Catalog and Discovery

Catalog resolves an exact ID and version to an explicitly registered value.
It guarantees registration. The consumer checks whether the value is valid
for its field. Catalog does not load modules, run work, or grant authority.

## Normal registration

Declare an Action, Flow, Agent, or Plugin through its normal DSL. The declaration
supplies registration data. Discovery collects it at startup. No second central
registration step is required. Action and Flow declarations also register their
input and output schemas; Agent declarations register their state schema.

Every reference has a string ID and positive integer version. Version defaults
to `1`. Module IDs default to the full module name. Named values use
`Provider/name`, including schemas such as `Elixir.MyApp.SendEmail/schema`.
Atoms default to `Provider/atom_name`. An explicit ID and version override these
defaults. A rename can change a default ID; set an explicit ID when saved JSON
must keep the same reference.

## Contributions from downstream packages

Any package can use the same mechanism. Define `__jido_catalog_manifest__/0`
on a module in its OTP application. Return a map or list of maps:

```elixir
defmodule MyApp.Values do
  def __jido_catalog_manifest__ do
    [
      %{target: MyApp.Connector},
      %{target: :connected},
      %{name: :request, target: Jido.Joi.object(%{query: Jido.Joi.string()})},
      %{id: "my_app/stable-value", vsn: 2, target: :legacy}
    ]
  end
end
```

Discovery supplies the provider and OTP application. Catalog has no Action,
Plugin, connector, or other semantic kinds. The owning package validates the
resolved value. Stored IDs never create atoms or select arbitrary module names.
Inline Actions remain private to their owners and are not discovered.

## Startup and refresh

Discovery starts an asynchronous Task. It does not delay full application
startup. Before publication, `Jido.Codec.decode/2` and `decode_json/2` return
an Issue with code `:catalog_not_ready`. The caller owns retries. A failed
initial build returns `:catalog_build_failed`. Both differ from an unknown
reference in a ready Catalog. Discovery's direct accessors raise a classified
Codec error with the same lifecycle code.

Normal hydration uses the current Catalog for each reference lookup. It does
not capture or pin a Catalog for the operation. A refresh can change the values
seen by later lookups. A missing reference fails resolution immediately.

Definitions added after startup need an explicit refresh:

```elixir
:ok = Jido.Catalog.Discovery.refresh()
```

Discovery scans loaded applications by default. Configure `applications:` and
`modules:` under `config :jido, Jido.Catalog.Discovery` to limit contributions.
Refresh replaces the complete Catalog and private Codec index together. Duplicate
ID/version pairs reject the build and report both sources. A failed refresh
keeps the last valid publication. Discovery does not add timers or retry loops.

## Explicit Catalogs for tests and exceptions

Pass an explicit Catalog to bypass the published Catalog:

```elixir
catalog = Jido.Catalog.from_targets!(MyApp.Values, :my_app, %{
  {"my_app/send-email", 1} => MyApp.SendEmail,
  {"my_app/connected", 1} => :connected
})

{:ok, MyApp.SendEmail} = Jido.Catalog.resolve(catalog, {"my_app/send-email", 1})
{:ok, {"my_app/connected", 1}} = Jido.Catalog.reference(catalog, :connected)

Jido.Codec.decode(document, catalog: catalog, codec: MyApp.DocumentCodec)
```

An explicit codec also avoids the published routing index. An explicit Catalog
alone does not replace that index when automatic document routing needs it.
Tests do not need to replace global application state.

`new/1` and `new!/1` accept Entries and Manifests. `get/3`, `get_by_target/2`,
and `list/1` expose registrations for inspection and explicit construction.
Multiple references can register the same value. Reverse lookup selects the
first reference in ID/version order. Duplicate ID/version pairs are always
rejected. Catalog has no filtered Views or revision API.

Hydration rejects registered module references when the module cannot load.
It does not defer missing-module failures to execution or compile source code.
Catalog itself continues to accept explicitly registered values without loading them.
