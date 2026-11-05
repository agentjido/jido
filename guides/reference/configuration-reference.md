# Configuration Reference

This guide lists every application config key, instance option, and AgentServer option in Jido, with its default and when it is read. For how to choose values, see [Production Setup](../operations/production-configuration.md).

Jido reads the `:jido` application environment and your own application's entry for an instance module. It reads no environment variable unless you use `Jido.Plugin.Config.env/1`.

## Precedence

For AgentServer options, the first value found wins:

1. An option passed to `Jido.start_agent/3` or `Jido.AgentServer.start_link/1`.
2. The instance's `:agent_server` option.
3. For `:turn_timeout` only, `config :jido, Jido.AgentServer`.
4. The default in [AgentServer options](#agentserver-options).

```elixir
defmodule ConfigRef.Invoice do
  use Jido.Agent, name: "config_ref_invoice"
end

{:ok, _} = Jido.start_link(name: ConfigRef.Jido, agent_server: [turn_timeout: 30_000])

{:ok, from_instance} = Jido.start_agent(ConfigRef.Jido, ConfigRef.Invoice, id: "invoice-1")
{:ok, from_call} = Jido.start_agent(ConfigRef.Jido, ConfigRef.Invoice, id: "invoice-2", turn_timeout: 5_000)

true = is_pid(from_instance) and is_pid(from_call)

{:error, %Jido.Error.ValidationError{message: "Jido instance options contain unknown keys"}} =
  Jido.start_link(name: ConfigRef.Bad, turn_timeout: 30_000)

{:error, %Jido.Error.ValidationError{message: "unknown startup options"}} =
  Jido.start_agent(ConfigRef.Jido, ConfigRef.Invoice, id: "invoice-3", retry: true)
```

Jido rejects an unknown or duplicate key instead of ignoring it.

## Application config

Set these with `config :jido, ...`. Each key is read at runtime, each time it is used, unless the table says otherwise.

| Key | Sub-key | Default | Read by | Effect |
| --- | --- | --- | --- | --- |
| `Jido.AgentServer` | `:turn_timeout` | `60_000` | `Jido.AgentServer` at startup | The default Turn bound. Any other sub-key is a startup error. |
| `Jido.Catalog.Discovery` | `:applications` | `:loaded` | `Jido.Catalog.Discovery` at each scan | The applications to scan: a list of atoms, or `:loaded`. Use an allowlist when you accept stored definitions from users. |
| `Jido.Catalog.Discovery` | `:modules` | `[]` | `Jido.Catalog.Discovery` at each scan | Extra modules to include, each an atom or `{module, application}`. |
| `Jido.Codec` | `:maximum_json_bytes` | `8_388_608` | `Jido.Codec` | The JSON size limit. A per-call `:maximum_json_bytes` option wins. |
| `Jido.Signal.Bus` | `:call_timeout` | `30_000` | `Jido.Signal.Bus` | The client call timeout in milliseconds. An invalid value uses the default. |
| `:max_concurrency` | None | The smaller of `System.schedulers_online/0` and `10` | `Jido.Exec` | The default concurrency for `Jido.Exec.run/4` and `Jido.Exec.start/6`. Turns do not use it. |
| `:max_payload_bytes` | None | `10_000_000` | `Jido.Signal.Codec` | The Signal payload limit. A per-call option wins. |
| `:normalize_dispatch_errors` | None | `false` | `Jido.Signal.Dispatch` | Returns a `Jido.Error.RoutingError` for a delivery failure and a `Jido.Error.ValidationError` for an invalid target, in place of the raw reason. The compile-time value is the fallback. |
| `:default_log_level` | None | `:info` | `Jido.Signal.Dispatch.LoggerAdapter` | The log level when the target sets none. |
| `:runtime_store_timeout` | None | `5_000` | Compile time | The call timeout for an instance's private runtime store. Recompile Jido after you change it. |
| `:telemetry` | `:semantic_log_mode` | `:off` | The default telemetry handler | `:off`, `:errors`, `:interesting`, or `:all`. See [Log modes](../operations/telemetry-tracing-and-logs.md#log-modes). |
| `:telemetry` | `:semantic_slow_threshold_ms` | `1_000` | The default telemetry handler | With `:interesting`, also logs events at least this slow. |
| `:opentelemetry` | `:enabled` | Enabled unless `false` | `Jido.Telemetry.open_telemetry?/0` | Set `false` to stop mapping events to spans. See [Metrics and OTel](../operations/metrics-and-open-telemetry.md). |
| `:ai_telemetry` | `:semantic_log_mode` | `:off` | `Jido.Telemetry.AI` | The same modes, for AI and model events. |
| `:ai_telemetry` | `:semantic_slow_threshold_ms` | `1_000` | `Jido.Telemetry.AI` | The same rule, for AI and model events. |
| `:ai_telemetry` | `:correlation_ttl_ms` | `3_600_000` | The AI correlation store | The lifetime of correlation entries. A value that is not a positive integer uses the default. |
| `:ai_telemetry` | `:correlation_sweep_interval_ms` | `60_000` | The AI correlation store | How often the store expires entries. Same validation. |
| `:ai_opentelemetry` | `:enabled` | Enabled unless `false` | `Jido.Telemetry.AI.open_telemetry?/0` | Set `false` to stop mapping AI events to spans. |
| `:ai_opentelemetry` | `:options` | `[]` | At application start | Options for `Jido.Telemetry.AI.attach_open_telemetry/1`. `:req_llm` holds the ReqLLM bridge's options, and its `:content` defaults to `:none`. |
| `:ai_inference_client` | None | `Jido.AI.InferenceClient.ReqLLM` | `Jido.AI.InferenceClient.Selection.client!/1` | The default [inference client](../ai/inference-clients.md). A `:jido_ai_inference_client` key in the Action context wins. |

The sub-key values accept a keyword list, or a map for the telemetry keys.

<!-- partial -->
```elixir
import Config

config :jido, :telemetry, semantic_log_mode: :interesting, semantic_slow_threshold_ms: 500
config :jido, Jido.Catalog.Discovery, applications: [:my_app, :jido]
config :jido, Jido.AgentServer, turn_timeout: 30_000
```

## Instance options

An instance is `use Jido` plus `config :my_app, MyApp.Jido, ...`, or a call to `Jido.start_link/1` or `Jido.start/1`.

| Option | Default | Allowed values | Effect |
| --- | --- | --- | --- |
| `:name` | Required for `Jido.start_link/1`. Jido.Default for `Jido.start/1`. The module, under `use Jido`. | A non-nil atom | The instance name. |
| `:otp_app` | None. Required by `use Jido`. | A non-nil atom | The application that holds the configuration. |
| `:namespace` | `nil` | A nonempty string | Stable identity for `Jido.Agent.Ref` functions and durable records. Required for persistent Agents. |
| `:persistence` | `nil` | A `Jido.Persistence.Store` module, `{module, options}`, `nil`, or `false` | The default adapter. |
| `:agent_server` | `[]` | A keyword list of [AgentServer options](#agentserver-options) | Defaults for each AgentServer in the instance. Validated at start. Startup-only options are rejected. |
| `:max_tasks` | `1_000` | A non-negative integer or `:infinity` | The child limit of the instance's Task supervisor. |
| `:debug` | Off | `nil`, `false`, `true`, or `:verbose` | Sets the instance log mode. `true` selects `:interesting` and `:verbose` selects `:all`. |

`use Jido` itself accepts only `:otp_app`, `:namespace`, and `:persistence`. Set the others in config or as `start_link` arguments. Options passed at start override config, and config overrides the `use` options, except `:name`, which is always the module.

Setting `agent_server: [persistence: :inherit]` without an instance `:persistence` is an error.

## AgentServer options

Set these in the instance's `:agent_server` option, or per Agent. Each timeout accepts milliseconds from `0` to `4_294_967_295`.

| Option | Default | Allowed values | Effect |
| --- | --- | --- | --- |
| `:turn_timeout` | `60_000` | Non-negative integer or `:infinity` | The bound from Turn start to commit. |
| `:exec_opts` | `[]` | See [Execution options](#execution-options) | Execution settings for each Turn. |
| `:error_policy` | `:log_only` | `:log_only`, `:stop_on_error`, `{:max_errors, n}`, `{:emit_signal, dispatch}`, or a two-argument function | The response to a failed Turn. See [Agent Lifecycle](../agent-servers/agent-activation-control.md). |
| `:error_policy_timeout` | `5_000` | A finite timeout | The bound on one policy run. |
| `:debug` | `false` | A boolean | Keeps Turn history for `Jido.AgentServer.history/1`. |
| `:debug_max_events` | `100` | `1` to `10_000` | The history limit. |
| `:max_postponed_signals` | `1_000` | Non-negative integer or `:infinity` | The queue limit. Past it, callers get `{:error, {:overloaded, details}}`. |
| `:max_directives_per_turn` | `1_000` | Non-negative integer or `:infinity` | The Directive batch limit. |
| `:directive_timeout` | `5_000` | A finite timeout | The bound on one Directive batch. |
| `:directive_handler` | `nil` | `nil` or a two-argument function | Runs Directives that no Plugin dispatches. |
| `:default_dispatch` | `nil` | `nil` or a dispatch target | The target for an Emit with no target. |
| `:readiness_timeout` | `5_000` | A finite timeout | The bound on Plugin startup and composition changes. |
| `:commit_timeout` | `5_000` | A finite timeout | The bound on Plugin `after_commit/3` callbacks in one Turn. |
| `:persistence` | `false` | A store, `{store, options}`, `:inherit`, `nil`, or `false` | Whether and where the Agent saves. The instance must have a `:namespace`. If it does not, the worker stops with `:stable_namespace_required` after start. |
| `:persistence_mode` | `:create` | `:create`, `:restore`, `:restore_or_create` | What startup does with a stored record. |
| `:persistence_timeout` | `5_000` | A finite timeout | The bound on one durable save or restore. |
| `:idle_timeout` | `:infinity` | A timeout or `:infinity` | The idle budget. |
| `:idle_policy` | `:stop` | `:stop`, or `:hibernate` with persistence | The action when the idle budget ends. |
| `:plugin_runtime_options` | `[]` | A keyword list per Plugin | See [Supervised Resources](../plugins/plugin-supervised-resources.livemd). |

These options are valid at startup only, not in the instance's `:agent_server`:

| Option | Default | Effect |
| --- | --- | --- |
| `:agent` | Set by `Jido.start_agent/3` | The Agent instance. Required by `Jido.AgentServer.start_link/1`. |
| `:jido` | Set by `Jido.start_agent/3` | The instance. |
| `:partition` | `nil` | A nonempty string that separates IDs within an instance. |
| `:name` | `nil` | An OTP name: an atom, `{:global, term}`, or `{:via, module, term}`. |
| `:runner` | The instance's Runner | A named Runic Runner that uses Jido's continuation store. |

`Jido.start_agent/3` also takes `:id` and `:state` for the new Agent.

Each call has its own options, such as `:timeout` and `:admission_timeout` on `Jido.AgentServer.call/3`, whose admission default is `5_000`. See [Admission and Deadlines](../agent-servers/agent-server-admission.md).

## Execution options

Pass these to `Jido.Exec.run/4` or in the AgentServer `:exec_opts` option.

| Option | Default | Allowed values | Effect |
| --- | --- | --- | --- |
| `:timeout` | `:infinity` | Non-negative integer or `:infinity` | Milliseconds for each attempt. |
| `:max_attempts` | `1` | Positive integer | Total attempts, including the first. |
| `:backoff` | `:none` | `:none`, `:linear`, `:exponential`, `:jitter` | The delay rule between attempts. |
| `:base_delay_ms` | `0` | Non-negative integer | The base for the delay rule. |
| `:max_delay_ms` | `0` | Non-negative integer | The upper limit for each delay. |
| `:max_concurrency` | `Jido.Exec`: `config :jido, :max_concurrency`. Turn: serial. | Positive integer | Concurrent Flow work. A Turn's Flow steps run one at a time unless you set this in `:exec_opts`. |
| `:task_supervisor` | The application's task supervisor | A local PID, registered name, or `{:via, module, name}` | The owner of the execution task. `Jido.Exec.run/4` only. |
| `:hooks` | None | A keyword list | `:exec_opts` only. Accepts `on_dispatch/2`, `on_complete/3`, `on_failed/3`, `on_idle/1`, `on_persistence_error/3`, and `transform_runnables/2`. |

See [Execution Policy](../actions/action-execution-policy.md).

## Persistence adapter options

See [Persistence Matrix](persistence-adapter-matrix.md#options).

## AI defaults

Reasoning Flows take their model, options, and limits as request input, not application config. See [Reasoning Matrix](reasoning-strategy-matrix.md). Configure model provider keys through ReqLLM, as [Configure ReqLLM](../ai/req-llm-configuration.livemd) shows.

## Plugin environment references

`Jido.Plugin.Config.env/1` stores a variable name in a Plugin option, so an Agent definition does not hold a secret. A Plugin's runtime calls `Jido.Plugin.Config.resolve/1` when it starts its resources. A missing variable is an error, and Jido does not convert the value's type. See [Supervised Resources](../plugins/plugin-supervised-resources.livemd).

## Related

- [Production Setup](../operations/production-configuration.md)
- [Instances and Tenants](../operations/configuration-and-tenant-isolation.md)
- [Telemetry Events](telemetry-event-reference.md)
