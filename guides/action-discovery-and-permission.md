# Action Discovery

`Jido.Discovery` builds a read-only catalog of the Action modules in your
release. Use it to list Actions in an admin screen, look one up by a stable
slug, or build a tool picker. It doesn't decide who can run an Action. This
guide shows the catalog, how to scope it, and how to keep a separate
allowlist for Agents and models.

```elixir
Jido.Discovery.list_actions(name: "order")
# => [
#      %{module: MyApp.Actions.LookupOrder, name: "lookup_order",
#        description: "Reads one order by ID", application: :my_app,
#        slug: "f5sthSdyusIigAKA"},
#      %{module: MyApp.Actions.RefundOrder, name: "refund_order",
#        description: "Refunds one order", application: :my_app,
#        slug: "hoedKUB-BfkpkxeW"}
#    ]
```

## The Catalog

Jido starts one temporary task at application start. The task scans the
module lists of the configured applications, keeps each module that has a
valid Action contract, and stores the result in `:persistent_term`. Reads
don't call Action code.

The first build takes time. Until it finishes, `catalog/0` returns
`{:error, :not_initialized}`, `list_actions/1` returns `[]`, and the lookups
return `nil`. Check `ready?/0` before you depend on the result:

```elixir
Jido.Discovery.ready?()
# => true

{:ok, built_at} = Jido.Discovery.last_updated()
```

Each entry holds:

| Key | Value |
| --- | --- |
| `module` | The Action module. |
| `name` | The Action's `name:`. |
| `description` | The Action's `description:`, or `nil`. |
| `application` | The OTP application that owns the module, or `nil`. |
| `slug` | 16 URL-safe characters derived from the module name. Stable across releases while the module name stays the same. |

Inline `action` blocks in routes are part of their Agent. Discovery skips
them.

## Query

```elixir
Jido.Discovery.list_actions(description: "Refunds")
Jido.Discovery.list_actions(application: :my_app, offset: 20, limit: 20)

Jido.Discovery.get_action(MyApp.Actions.RefundOrder)
Jido.Discovery.get_action_by_slug("hoedKUB-BfkpkxeW")
```

`name:` and `description:` are case-sensitive substring matches.
`application:` is exact. Results are sorted by name.

For the input schema, call the Action module. `to_json/0` returns a map with
string keys, including `"description"` and `"input_schema"` as JSON Schema.

## Scope the Scan

By default Discovery scans every loaded application, including Jido and your
dependencies. Limit it to the applications that own your Actions:

```elixir
# config/config.exs
config :jido, Jido.Discovery,
  applications: [:my_app],
  modules: [MyApp.Scripts.Backfill]
```

`modules:` adds Actions that aren't in a listed application. Set
`applications: []` to scan only `modules:`.

> #### Set an allowlist {: .warning}
>
> The default scan includes Jido's internal Actions. It can also report
> diagnostics for modules that fail to load, such as Hex modules under
> `mix`. An `applications:` list keeps the catalog to your own code and
> makes the first build faster.

`refresh/1` rebuilds and replaces the whole catalog. It takes the same
options:

```elixir
:ok = Jido.Discovery.refresh(applications: [:my_app])

Jido.Discovery.refresh(applications: [:nope])
# => {:error, {:application_not_loaded, :nope}}
```

A failed refresh keeps the previous catalog. `catalog/0` returns the full
map, with `diagnostics` for modules that looked like Actions but failed
validation.

## Not Permission

The catalog lists what exists in the release. Any code that holds a module
name can run that Action, whether or not it is in the catalog. Don't use the
catalog to decide what a user, tenant, Agent, or model is allowed to call.

Jido gives you two places to set that limit.

### Agent Routes

An Agent runs only the Actions and Flows bound in its routes. A Signal
selects a route by type. It can't name an Action module. A type with no
route fails the Turn with `"No route accepts this Signal type"`.

Keep each route narrow, and use `emits:` to limit the Signal types a route
can emit. The route table is the Agent's complete list of operations. See
[Routes and Handlers](build-agent-routes.livemd).

### Your Allowlist

When a model or a client picks an Action by name, look it up in a list you
own. Keep the list in code or in your database, keyed by role, tenant, or
Agent:

```elixir
defmodule MyApp.Tools do
  @allowed %{
    "support" => [MyApp.Actions.LookupOrder],
    "billing" => [MyApp.Actions.LookupOrder, MyApp.Actions.RefundOrder]
  }

  def for_role(role), do: Map.get(@allowed, role, [])

  def run(role, name, params) do
    case Enum.find(for_role(role), &(&1.name() == name)) do
      nil -> {:error, :not_allowed}
      action -> Jido.Exec.run(action, params)
    end
  end
end

MyApp.Tools.run("support", "refund_order", %{order_id: "o-1"})
# => {:error, :not_allowed}

MyApp.Tools.run("billing", "refund_order", %{order_id: "o-1"})
# => {:ok, %{order_id: "o-1", refunded: true}}
```

Give the model only the tool descriptions from `for_role/1`, and check the
name again when the model calls it. The model's request is input. Treat it
like any other client data.

Use the catalog to build the admin screen where someone edits that list.
Store module names or slugs, and resolve them back with `get_action/1` or
`get_action_by_slug/1`. A `nil` result means the Action no longer exists in
the release.

## Next

- [Routes and Handlers](build-agent-routes.livemd) – bind Actions to Signal
  types.
- [Instances and Tenants](configuration-and-tenant-isolation.md) – what the
  shared catalog means for multi-tenant systems.
