# Agent Plugins

Use a Plugin to add validated authoring data, Agent behavior, or live runtime
behavior. Jido uses one Plugin declaration format for all three cases.

This guide assumes that you read
[Define an Agent](define-and-instantiate-an-agent.livemd).

## Declare a Plugin

The `plugins:` Agent option accepts an ordered list. Each item is a Plugin
module or a `{Plugin, config}` tuple. The config must be a static map with atom
keys.

```elixir
defmodule MyApp.Labels do
  @section %Spark.Dsl.Section{
    name: :labels,
    schema: [owner: [type: :string, required: true]]
  }

  @schema Zoi.object(
            %{owner: Zoi.string() |> Zoi.min(1)},
            unrecognized_keys: :error
          )

  use Jido.Plugin,
    id: "my_app.labels",
    vsn: 1,
    sections: [@section]

  @impl true
  def lower(dsl, config) do
    owner = Spark.Dsl.Extension.get_opt(dsl, [:labels], :owner)
    {:ok, Map.put(config, :owner, owner)}
  end

  @impl true
  def normalize(data), do: Zoi.parse(@schema, data)
end

defmodule MyApp.Support do
  use Jido.Agent,
    name: "support",
    plugins: [MyApp.Labels]

  state do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
  end

  labels do
    owner("support-team")
  end
end
```

The definition stores one canonical contribution:

```elixir
MyApp.Support.definition().plugins
# => [%{provider: MyApp.Labels, id: "my_app.labels", vsn: 1,
#       data: %{owner: "support-team"}}]
```

This Plugin has no runtime callbacks. It adds authoring data only, so Jido does
not create a runtime manifest for it.

## Authoring Callbacks

Three callbacks shape Plugin authoring data. They must be deterministic and
must not start processes or do I/O.

| Callback | Use |
| --- | --- |
| `lower/2` | Merge custom DSL data and the declared config map. |
| `normalize/1` | Validate data from the DSL, maps, or the Agent codec. |
| `verify/2` | Check the Plugin data against the complete Agent definition. |

Use the `imports:` option when a Plugin must import helper macros into an Agent
module. Jido passes these modules to Spark as module imports.

## Add Runtime Behavior

A Plugin gets a runtime manifest only when it implements a runtime callback.
Jido detects the callback owners at compile time.

```elixir
defmodule MyApp.Throttle do
  use Jido.Plugin,
    id: "my_app.throttle",
    option_keys: [agent: [:label], agent_server: [:limit]]

  @impl true
  def prepare(preparation, opts) do
    {:ok, %{label: opts[:label], signal_id: preparation.signal.id}}
  end

  @impl true
  def validate_options(opts) do
    if is_integer(opts[:limit]) and opts[:limit] > 0,
      do: :ok,
      else: {:error, :invalid_limit}
  end

  @impl true
  def admit(_runtime, _admission, opts), do: {:ok, %{limit: opts[:limit]}}
end

defmodule MyApp.SupportDesk do
  use Jido.Agent,
    name: "support_desk",
    plugins: [{MyApp.Throttle, %{label: "support", limit: 10}}]
end
```

On a live Agent Server, an Action can read both Plugin inputs:

```elixir
context.plugin_inputs[MyApp.Throttle]
# => %Jido.Plugin.Input{
#      prepared: %{label: "support", signal_id: "01a15716-..."},
#      runtime: %{limit: 10}
#    }
```

`Jido.Agent.cmd/3` runs `prepare/2`. It does not run `admit/3`, so the runtime
input is `nil` for a pure command.

## Runtime Callback Owners

Jido groups runtime callbacks by the component that calls them.

| Callback | Owner | Use |
| --- | --- | --- |
| `state_spec/1` | Agent | Add one owned field to Agent state. |
| `directives/1` | Agent | Claim custom Directive types. |
| `prepare/2` | Agent | Prepare input before route selection. |
| `select_route/2` | Agent | Select one matching route. |
| `reduce/2` | Agent | Update owned state after route execution. |
| `validate_options/1` | Agent Server | Validate live Plugin options. |
| `admit/3` | Agent Server | Accept or reject live input. |
| `child_spec/1` | Agent Server | Start one supervised runtime root. |
| `await_ready/2` | Agent Server | Wait for the runtime root. |
| `after_commit/3` | Agent Server | Run after commit and before Directives. |
| `dispatch/4` | Agent Server | Dispatch one owned Directive. |
| `prepare_outbound/4` | Agent Server | Prepare one outbound Signal. |
| `quiesce/2`, `resume/2` | Agent Server | Pause and resume around a live change. |
| `dump/3`, `load/3` | Persistence | Convert owned state for storage. |

## Contract Rules

Jido rejects invalid callback combinations:

- `reduce/2` requires `state_spec/1`.
- `dump/3` and `load/3` require owned state and must occur together.
- `quiesce/2` and `resume/2` must occur together.
- `dispatch/4` requires an owned Directive.
- Two Plugins cannot own the same state key or Directive type.

Set `id:` for a stable authoring identity. Set `vsn:` when the Plugin data
contract changes. The default version is `1`.
