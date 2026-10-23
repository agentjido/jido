# Extensions or Plugins

You need every Agent to carry an owner label, reject Signals with no actor,
or hold a database connection. Jido has two contracts for that. An
**Extension** adds validated data to an Agent definition. A **Plugin** adds
behavior: it sees Signals, owns a state field, and runs processes.

This guide shows both and how to pick one. It assumes you've read
[Define an Agent](define-and-instantiate-an-agent.livemd).

## At a Glance

| | Extension | Plugin |
| --- | --- | --- |
| Module | `use Jido.Agent.Extension` | `use Jido.Plugin` |
| Adds | Static data on the definition | Behavior on every Turn and at runtime |
| Agent state | None | Optionally one owned field |
| Sees Signals | No | `prepare/2` and `admit/3` |
| Runs processes | No | Optionally one supervised runtime root |
| Directives | None | Can own and dispatch custom Directives |

`use Jido.Plugin` builds on `use Jido.Agent.Extension`, so every Plugin is
also an Extension. Start with an Extension. Switch to a Plugin when the
code has to see a Signal, own state, or hold a process.

## Write an Extension

This Extension records which team owns an Agent. It adds a `labels` section
to the Agent DSL:

```elixir
defmodule MyApp.Labels do
  @section %Spark.Dsl.Section{
    name: :labels,
    schema: [owner: [type: :string, required: true]]
  }
  @schema Zoi.object(%{owner: Zoi.string() |> Zoi.min(1)}, unrecognized_keys: :error)

  use Jido.Agent.Extension, id: "my_app.labels", vsn: 1, sections: [@section]

  @impl Jido.Agent.Extension
  def lower(dsl, config) do
    {:ok, Map.put(config, :owner, Spark.Dsl.Extension.get_opt(dsl, [:labels], :owner))}
  end

  @impl Jido.Agent.Extension
  def normalize(data), do: Zoi.parse(@schema, data)
end

defmodule MyApp.Support do
  use Jido.Agent,
    name: "support",
    extensions: [MyApp.Labels]

  agent do
    schema(Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}))
  end

  labels do
    owner("support-team")
  end
end
```

The definition now carries one contribution:

```elixir
MyApp.Support.definition().extensions
# => [%{provider: MyApp.Labels, id: "my_app.labels", vsn: 1,
#       data: %{owner: "support-team"}}]
```

That's the whole effect. A dashboard, router, or audit tool can read the
label. The Agent never runs any Extension code at Turn time, and
`MyApp.Labels.runtime_support()` returns `:none`.

Three callbacks shape the data. Jido calls them when it builds or validates a
definition. Keep them deterministic: no processes, no Actions, no I/O.

| Callback | Invoked when |
| --- | --- |
| `lower/2` | The DSL compiles. Turns DSL declarations and config into a data map. |
| `normalize/1` | Any authoring path validates the entry: DSL, `Jido.Agent.define/1`, or the Codec. |
| `verify/2` | Jido checks the entry against the complete definition. |

### Store Typed Authoring Data

The Agent Codec must make Extension data safe for JSON. The default Extension
implementation uses `Jido.Authoring.Value`. This works for maps, lists, strings,
numbers, booleans, and other supported values.

Override `encode_authoring_data/2` and `decode_authoring_data/2` when the data
contains typed references. For example, a Plugin can store an Action, a Flow,
or a schema. Use the trusted `Jido.Authoring.Registry` that Jido passes to each
callback:

```elixir
@impl Jido.Agent.Extension
def encode_authoring_data(%{action: action}, registry) do
  with {:ok, reference} <-
         Jido.Authoring.Registry.encode_reference(registry, :action, action) do
    {:ok, %{"action" => reference}}
  end
end

@impl Jido.Agent.Extension
def decode_authoring_data(%{"action" => reference}, registry) do
  with {:ok, action} <-
         Jido.Authoring.Registry.decode_reference(registry, reference, :action) do
    {:ok, %{action: action}}
  end
end
```

Jido resolves the Extension provider through the Registry before it calls the
decoder. The Registry must also contain each referenced Action, Flow, or schema.
Do not create atoms or modules from JSON input. Keep both callbacks deterministic
and free of runtime work.

## Write a Plugin

A Plugin implements any of the `Jido.Plugin` callbacks. Jido reads which
ones you defined and enables those capabilities. There are no roles or
flags to set.

```elixir
defmodule MyApp.Throttle do
  use Jido.Plugin, option_keys: [agent: [:label], agent_server: [:limit]]

  @impl true
  def prepare(preparation, opts),
    do: {:ok, %{label: opts[:label], signal_id: preparation.signal.id}}

  @impl true
  def validate_options(opts) do
    if is_integer(opts[:limit]) and opts[:limit] > 0,
      do: :ok,
      else: {:error, :invalid_limit}
  end

  @impl true
  def admit(_runtime, _admission, opts), do: {:ok, %{limit: opts[:limit]}}
end
```

Declare it in the `agent` block and pass options with `config:`:

```elixir
defmodule MyApp.SupportDesk do
  use Jido.Agent, name: "support_desk"

  agent do
    schema(Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}))
    plugin MyApp.Throttle, config: %{label: "support", limit: 10}
  end
end
```

On a live Server, an Action on this Agent sees both inputs:

```elixir
context.plugin_inputs[MyApp.Throttle]
# => %Jido.Plugin.Input{
#      prepared: %{label: "support", signal_id: "01a15716-..."},
#      runtime: %{limit: 10}
#    }
```

`cmd/3` runs `prepare/2` but not `admit/3`, so `runtime` is `nil` there.

The `plugin` declaration is the source of the Plugin provider and its config.
It works in source files, generated modules, and Livebook cells. Add a provider
to `extensions:` only when it adds custom Spark sections that must be available
before the Agent body is parsed. An Extension with no `plugin` declaration gets
an empty config.

A Plugin's contribution `id` defaults to the module name as a string,
`"Elixir.MyApp.Throttle"`. Set `id:` in `use Jido.Plugin` for a stable name,
and `vsn:` for its version (default `1`).

## Callback Owners

Jido groups Plugin callbacks by who calls them. It selects the groups from the
callbacks that the Plugin implements.

| Callback | Owner | Invoked when |
| --- | --- | --- |
| `state_spec/1` | Agent | Jido composes the Agent state schema. |
| `directives/1` | Agent | Jido normalizes the Plugin, to claim Directive types. |
| `prepare/2` | Agent | Before route selection, on every Turn, in `cmd/3` and on a live Server. |
| `reduce/2` | Agent | After the Action or Flow succeeds, before state validation. |
| `validate_options/1` | Agent Server | Every normalization: definition, startup, live change. |
| `admit/3` | Agent Server | After `prepare/2`, live Server only. |
| `child_spec/1` | Agent Server | The activation starts, recovers, or replaces the runtime. |
| `await_ready/2` | Agent Server | After all runtime roots start, before the first Turn. |
| `after_commit/3` | Agent Server | After each commit, before Directives. |
| `dispatch/4` | Agent Server | After commit, once per owned Directive. |
| `prepare_dispatch/4` | Agent Server | Before each outbound Signal from `Emit`, `AgentSend`, or `ParentSend`. |
| `quiesce/2`, `resume/2` | Agent Server | Around a live change to this Plugin. |
| `dump/3`, `load/3` | Persistence | When owned state is saved and restored. |

## Option Keys

Without `option_keys:`, every callback receives every option. With it, each
owner sees only its keys. For `MyApp.Throttle`, Agent callbacks receive
`[label: "support"]` and Agent Server callbacks receive `[limit: 10]`.

`validate_options/1` checks the Agent Server options. An invalid value fails
Agent definition validation with the reason you return.

## Shape Rules

Jido rejects a Plugin whose callbacks don't fit together:

- `reduce/2` requires `state_spec/1`.
- `dump/3` and `load/3` require an owned state field and come as a pair.
- `quiesce/2` and `resume/2` come as a pair.
- `dispatch/4` requires at least one owned Directive.
- Each owned Directive must be reduced or dispatched.
- Two Plugins can't own the same state key or Directive type.

The check runs when the Agent module compiles. A `reduce/2` without
`state_spec/1` fails the build with:

```text
** (Jido.Error.ValidationError) Agent Plugin reduce/2 requires state_spec/1
```

## Choose One

| You want to | Use |
| --- | --- |
| Attach labels, policies, or metadata to a definition | Extension |
| Add DSL syntax that lowers to validated data | Extension |
| Reject or enrich every Signal before the route runs | Plugin with `prepare/2` |
| Check live credentials, quotas, or leases | Plugin with `admit/3` |
| Track a value across every Turn | Plugin with `state_spec/1` and `reduce/2` |
| Hold a connection, cache, or timer for one Agent | Plugin with `child_spec/1` |
| Run a custom effect after commit | Plugin with `directives/1` and `dispatch/4` |
| Store owned state in a different shape | Plugin with `dump/3` and `load/3` |

## What Neither Can Do

No Extension or Plugin can:

- replace the incoming Signal, the caller context, or the selected route;
- change Agent state outside its own owned field;
- read or change private Agent Server state; or
- run runtime work before commit.

These limits are why ten Plugins on one Agent still produce one predictable
Turn.

## Next

- [Stateful Plugins](write-a-stateful-plugin.livemd): own a state field and
  check every Signal.
- [Supervised Resources](plugin-supervised-resources.livemd): give a Plugin a
  process.
- [Custom Directives](plugin-custom-directives.livemd): run work after commit.
- [Plugin Persistence](plugin-persistence-and-live-changes.md): save Plugin
  state and change Plugins on a running Agent.
