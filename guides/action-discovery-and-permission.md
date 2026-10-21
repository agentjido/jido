# Authoring Discovery and Permission

`Jido.Discovery` is owned by `jido_action`. It builds one immutable
`Jido.Authoring.Registry` for Actions, Flows, Agents, extensions, Plugins,
schemas, atoms, and document codecs.

`jido_action` refreshes this Registry in one temporary startup task. The task
scans all loaded OTP applications, including packages such as `jido_chat` and
`jido_connect` when they are present. An application can refresh it with an
explicit application list:

```elixir
:ok = Jido.Discovery.refresh(applications: [:jido_action, :jido, :my_app])
```

Use `Jido.Discovery.ready?/0` when application startup work needs the catalog.
If the initial scan fails, it stays false and `Jido.Discovery.registry/0`
raises with the scan reason.

Use stable `id:` and `vsn:` values for definitions that can appear in stored
documents:

```elixir
defmodule MyApp.Actions.LookupOrder do
  use Jido.Action,
    id: "my_app/actions/lookup-order",
    vsn: 1,
    name: "lookup_order"

  def run(params, _context), do: {:ok, params}
end

defmodule MyApp.SupportAgent do
  use Jido.Agent,
    id: "my_app/agents/support",
    name: "support_agent"
end
```

Agent extensions and Plugins publish the same manifest:

```elixir
defmodule MyApp.Labels do
  use Jido.Agent.Extension, id: "my_app/extensions/labels", vsn: 1
end

defmodule MyApp.Audit do
  use Jido.Plugin, id: "my_app/plugins/audit", vsn: 1
  def state_spec(_opts), do: :none
end
```

## Query the Registry

```elixir
Jido.Discovery.list(:action)
Jido.Discovery.list(:agent)
Jido.Discovery.list(:plugin)

Jido.Discovery.get("my_app/actions/lookup-order", 1)
Jido.Discovery.get_by_target(:agent, MyApp.SupportAgent)
```

Each entry includes its stable ID, version, kind, target, provider, and owning
application. Actions, Flows, and Agents can also include display text.

The Registry uses `{id, vsn}` references in Elixir:

```elixir
registry = Jido.Discovery.registry()

{:ok, MyApp.Actions.LookupOrder} =
  Jido.Authoring.Registry.resolve(
    registry,
    {"my_app/actions/lookup-order", 1},
    :action
  )
```

Stored JSON keeps the same version:

```json
{
  "id": "my_app/actions/lookup-order",
  "vsn": 1
}
```

## Discovery Is Not Permission

Discovery lists trusted code that is present in the release. It does not give
a user, tenant, Agent, or model permission to run that code.

Agent routes define the operations that one Agent can select. Products must
keep a separate allowlist when a user or model can select an Action directly.

```elixir
defmodule MyApp.Tools do
  @allowed %{
    "support" => [MyApp.Actions.LookupOrder],
    "billing" => [MyApp.Actions.LookupOrder, MyApp.Actions.RefundOrder]
  }

  def for_role(role), do: Map.get(@allowed, role, [])
end
```

Do not build a Registry from stored input. Define trusted manifests in code,
review changes to them, and use stored data only to select existing Registry
entries.
