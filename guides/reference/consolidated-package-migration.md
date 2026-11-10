# Package Consolidation

This guide moves an application from the four split Jido V3 packages, `jido`, `jido_action`, `jido_signal`, and `jido_ai`, to the one `:jido` package. Each section lists what changes in your code. If you are still on V2, read [V2 to V3 Migration](v2-to-v3-migration.md) as well.

Old module names that no longer exist are written here in plain text. Current names are in code font.

## What was compared

The old side of each table comes from these sources. A version on another branch can differ.

| Package | Source | `mix.exs` version |
| --- | --- | --- |
| `jido` | Branch `release/v3`, commit `21d0dd4c` | `3.0.0-beta.2` |
| `jido_action` | Tag `v3.0.0-beta.22` | `3.0.0-beta.22` |
| `jido_signal` | Branch `release/v3`, commit `7b825f1` | `3.0.0-beta.5` |
| `jido_ai` | Branch `release/v3`, commit `2d3cac67` | `2.3.0` |

The new package's `mix.exs` version is `0.1.0`. This guide states no Hex version, because none is recorded in the source.

## Change your dependencies

Remove the four dependencies and add one.

<!-- partial -->
```elixir
def deps do
  [
    # Removes {:jido, ...}, {:jido_action, ...}, {:jido_signal, ...}, {:jido_ai, ...}
    {:jido, github: "agentjido/jido", branch: "migration/consolidated-v3"}
  ]
end
```

Elixir `~> 1.18` is still required. `:jido` now brings `req_llm`, `runic`, `spark`, `splode`, `sched_ex`, `yaml_elixir`, `zoi`, `telemetry`, `telemetry_metrics`, and `multigraph` for every application, including one with no AI Agents. It requires `zoi ~> 0.19.0`, where `jido` and `jido_action` required `~> 0.18.11`.

These remain optional. Add one only if you use it: `bedrock` and `bedrock_raft`, `ecto_sql`, `opentelemetry_api`, and `phoenix_pubsub`.

## Application startup

The package has one OTP application, `:jido`, and one application module. It starts what the three removed application modules used to start. Remove any reference to `:jido_action`, `:jido_signal`, or `:jido_ai` from your `extra_applications` or `included_applications`.

| Removed | Its children now start under `:jido` |
| --- | --- |
| Jido.Signal.Application | The `Jido.Signal.Bus` name registry |
| Jido.Action.Application | The `Jido.Exec` task supervisor, and `Jido.Catalog.Discovery` in place of Jido.Discovery |
| Jido.AI.Application | The AI telemetry correlation store. The AI telemetry handlers attach at start. |

See [Module and Namespace Map](module-and-namespace-map.md#process-trees) for the tree.

## Move your configuration

Every key now lives under `:jido`. A value under an old application name is ignored without an error.

| Old key | New key |
| --- | --- |
| `config :jido_action, Jido.Authoring, maximum_json_bytes: n` | `config :jido, Jido.Codec, maximum_json_bytes: n` |
| `config :jido_action, Jido.Discovery, ...` | `config :jido, Jido.Catalog.Discovery, ...` |
| `config :jido_signal, :max_payload_bytes` | `config :jido, :max_payload_bytes` |
| `config :jido_signal, :default_log_level` | `config :jido, :default_log_level` |
| `config :jido_signal, :normalize_dispatch_errors` | `config :jido, :normalize_dispatch_errors` |
| `config :jido_ai, :inference_client` | `config :jido, :ai_inference_client` |
| `config :jido_ai, :telemetry` | `config :jido, :ai_telemetry` |
| `config :jido_ai, :opentelemetry` | `config :jido, :ai_opentelemetry` |

`config :jido, :telemetry`, `config :jido, :opentelemetry`, `config :jido, Jido.AgentServer`, and `config :jido, :runtime_store_timeout` keep their names. See the [Configuration Reference](configuration-reference.md).

## Change your schemas

`Jido.Joi` is now the schema API, and every Jido guide uses it. Replace `Zoi.` with `Jido.Joi.` in Action, Flow, Signal, and Agent schemas. A Joi schema is an ordinary Zoi schema, so a remaining `Zoi` schema still runs. The two differ on undeclared fields, which can change your data:

```elixir
defmodule PackageGuide.WithZoi do
  use Jido.Action, name: "with_zoi", schema: Zoi.object(%{sku: Zoi.string()})

  @impl true
  def run(params, _context), do: {:ok, params}
end

defmodule PackageGuide.WithJoi do
  use Jido.Action, name: "with_joi", schema: Jido.Joi.object(%{sku: Jido.Joi.string()})

  @impl true
  def run(params, _context), do: {:ok, params}
end

{:ok, %{sku: "a-1"}} = Jido.Exec.run(PackageGuide.WithZoi, %{sku: "a-1", note: "rush"})
{:ok, %{sku: "a-1", note: "rush"}} = Jido.Exec.run(PackageGuide.WithJoi, %{sku: "a-1", note: "rush"})
```

Set `unrecognized_keys: :error` when an undeclared field must fail. See [Jido.Joi Validation](../data/joi-validation.md).

## Replace renamed modules

These modules moved or merged. Each row is checked against the current build.

| Old module | Package | Replacement |
| --- | --- | --- |
| Jido.Discovery | `jido_action` | `Jido.Catalog.Discovery`. Also `Jido.Catalog` for entry values. |
| Jido.Authoring | `jido_action` | `Jido.Codec`, with `decode/2`, `decode_json/2`, `encode/2`, and `encode_json/2` |
| Jido.Authoring.Issue | `jido_action` | `Jido.Codec.Issue` |
| Jido.Exec.Telemetry | `jido_action` | `Jido.Telemetry.Exec` |
| Jido.Signal.ID | `jido_signal` | `Jido.Id` |
| Jido.Signal.Serialization | `jido_signal` | `Jido.Signal.Codec` |
| Jido.Signal.Telemetry | `jido_signal` | `Jido.Telemetry.Signal` |
| Jido.Signal.Trace | `jido_signal` | `Jido.Trace` for the value, `Jido.Signal.Context` to read or write it on a Signal |
| Jido.Tracing.Trace | `jido` | `Jido.Trace` |
| Jido.Tracing.Context | `jido` | `Jido.Trace.Context` |
| Jido.Agent.Command | `jido` | `Jido.AgentServer.Command` |
| Jido.AgentServer.Directive.AgentSend | `jido` | `Jido.Agent.Directive.AgentSend` |
| Jido.AgentServer.Directive.ParentSend | `jido` | `Jido.Agent.Directive.ParentSend` |
| Jido.AgentServer.Directive.ServerStop | `jido` | `Jido.Agent.Directive.ServerStop` |
| Jido.Config | `jido` | `Jido.Plugin.Config` |
| Jido.Persistence.Adapter | `jido` | `Jido.Persistence.Store` |
| Jido.Plugin.Bus | `jido` | `Jido.Plugin.Bus.Manager` and `Jido.Plugin.Bus.Client`, which it only described |
| Jido.Schema | `jido` | Private. Use `Jido.Joi`. |
| Jido.AI.Telemetry | `jido_ai` | `Jido.Telemetry.AI` |
| Each Flow's Actions.ExpandNext, such as Jido.AI.Reasoning.TRM.Actions.ExpandNext | `jido_ai` | `Jido.AI.Reasoning.Actions.ExpandDecision` |

Internal modules also moved or merged. If you called one, such as Jido.Agent.Options, Jido.RuntimeStore, Jido.Instance.RefFacade, Jido.Signal.Sanitizer, or Jido.Exec.Portable, stop and use a public module from the [Module and Namespace Map](module-and-namespace-map.md).

## Replace error modules

Four error namespaces merged into `Jido.Error`. Rescue and match the new structs, and build errors through `Jido.Error` functions.

| Old | New |
| --- | --- |
| Jido.Action.Error.InvalidInputError, Jido.Signal.Error.InvalidInputError | `Jido.Error.ValidationError` |
| Jido.Action.Error.ConfigurationError | `Jido.Error.ValidationError`, with `kind: :config` |
| Jido.Action.Error.ExecutionFailureError, Jido.Signal.Error.ExecutionFailureError | `Jido.Error.ExecutionError` |
| Jido.Action.Error.TimeoutError, Jido.Signal.Error.TimeoutError | `Jido.Error.TimeoutError` |
| Jido.Action.Error.InternalError, Jido.Signal.Error.InternalError | `Jido.Error.InternalError` |
| Jido.Signal.Error.RoutingError, Jido.Signal.Error.DispatchError | `Jido.Error.RoutingError` |
| Jido.Agent.Error, Jido.Flow.Error, Jido.Flow.FieldError | `Jido.Error.ValidationError`. See [Jido Error Contracts](../data/error-contracts.md). |
| Jido.Plugin.Error | `Jido.Error.ExecutionError` for a callback that raises, and `Jido.Error.ValidationError` for an invalid result |

```elixir
defmodule PackageGuide.Counter do
  use Jido.Agent, name: "package_guide_counter"
end

agent = PackageGuide.Counter.instantiate!(id: "counter-1")
signal = Jido.Signal.new!("order.unknown", %{}, source: "/orders")

{:error, %Jido.Error.ValidationError{code: :unmatched_input, message: "No route accepts this Signal type"}} =
  PackageGuide.Counter.cmd(agent, signal)

{:error, %Jido.Error.ValidationError{kind: :config}} =
  Jido.Exec.run(PackageGuide.WithJoi, %{sku: "a-1"}, %{}, max_retries: 3)
```

## Replace changed functions

`use Jido` no longer generates a runtime API. Earlier, an instance module had functions such as `MyApp.Jido.start_agent/2`, `MyApp.Jido.call/3`, and `MyApp.Jido.hibernate/2`. Now it has only `child_spec/1`, `start_link/1`, and `config/1`, so pass the instance as the first argument to `Jido`.

| Old | New |
| --- | --- |
| `MyApp.Jido.start_agent(agent, opts)` | `Jido.start_agent(MyApp.Jido, agent, opts)` |
| `MyApp.Jido.stop_agent(id)`, `whereis_agent(id)`, `list_agents()`, `agent_count()` | `Jido.stop_agent/3`, `Jido.whereis_agent/3`, `Jido.list_agents/2`, `Jido.agent_count/2`, each with the instance first |
| `MyApp.Jido.call(ref, signal)` and the other Ref functions | `Jido.call(MyApp.Jido, ref, signal)` and the same pattern |
| `MyApp.Jido.hibernate(server)`, `thaw(module, id)` | `Jido.hibernate(MyApp.Jido, server)`, `Jido.thaw(MyApp.Jido, module, id)` |
| Jido.await, Jido.abandon, and `MyApp.Jido.await/2` | `Jido.AgentServer.await/2`, `Jido.AgentServer.abandon/1` |
| Jido.debug and `MyApp.Jido.debug/1` | The `:debug` [instance option](configuration-reference.md#instance-options) |
| Jido.registry_name, `task_supervisor_name`, and the other name functions | None. These names are private. |
| Jido.AgentServer.Directive.agent_send, parent_send, server_stop | `Jido.Agent.Directive.agent_send/2`, `Jido.Agent.Directive.parent_send/1`, `Jido.Agent.Directive.server_stop/1` |
| Jido.Signal.to_map, from_map, serialize, deserialize | `Jido.Signal.Codec.to_map/1`, `Jido.Signal.Codec.from_map/1`, `Jido.Signal.Codec.serialize/2`, `Jido.Signal.Codec.deserialize/2` |
| Jido.AI.InferenceClient.client! | `Jido.AI.InferenceClient.Selection.client!/1` |
| Jido.AI.Toolset.from_context | `Jido.AI.ToolSource.from_context/1`, which returns tool specs |

```elixir
{:ok, _} = Jido.start_link(name: PackageGuide.Jido, namespace: "package-guide/agents")

{:ok, server} = Jido.start_agent(PackageGuide.Jido, PackageGuide.Counter, id: "counter-2")
^server = Jido.whereis_agent(PackageGuide.Jido, "counter-2")
1 = Jido.agent_count(PackageGuide.Jido)

{:ok, ref} = Jido.agent_ref(PackageGuide.Jido, "counter-2")
%{id: "counter-2"} = Jido.agent(PackageGuide.Jido, ref)

signal = Jido.Signal.new!("order.placed", %{id: "o-1"}, source: "/orders")
%{"type" => "order.placed"} = Jido.Signal.Codec.to_map(signal)
```

`Jido.Exec`, `Jido.Instruction`, `Jido.Flow`, `Jido.Signal.Router`, `Jido.Signal.Dispatch`, `Jido.Signal.Bus`, `Jido.Agent`, `Jido.Persistence`, and `Jido.AI.Reasoning` keep the public function names they had in the sources above.

## Update telemetry handlers

Handlers keep working with the same event prefixes: `[:jido, :agent_server]`, `[:jido, :persistence]`, `[:jido, :action]`, `[:jido, :flow]`, `[:jido, :dispatch]`, `[:jido, :signal, :bus]`, and `[:jido, :ai]`. Update the module names that you call, as in [Replace renamed modules](#replace-renamed-modules). See [Telemetry Events](telemetry-event-reference.md).

## Checklist

1. Replace the four dependencies with one, and remove the old application names.
2. Move each configuration key to `:jido`.
3. Replace Zoi calls with `Jido.Joi`, and decide the unknown-key policy for each schema.
4. Rename modules, and match `Jido.Error` structs.
5. Pass the instance to `Jido` functions in place of the generated instance API.
6. Run your tests. An unknown old module name fails at compile time or as `UndefinedFunctionError`, while a moved configuration key fails silently, so check step 2 by reading your config files.

## Related

- [V2 to V3 Migration](v2-to-v3-migration.md)
- [Module and Namespace Map](module-and-namespace-map.md)
- [Configuration Reference](configuration-reference.md)
