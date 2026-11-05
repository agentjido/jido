# Production Setup

Follow these steps to take a Jido instance from development defaults to a configured production service. Each step names the setting and the behavior it changes. For every option, see the [Configuration Reference](../reference/configuration-reference.md).

## Add the instance to your tree

Define one instance module and put it after the services that its Agents use. Supervisors stop children in reverse order, so this stops your Agents before your database connection.

<!-- partial -->
```elixir
defmodule MyApp.Jido do
  use Jido, otp_app: :my_app, namespace: "my-app/primary"
end

defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MyApp.Repo,
      MyApp.Jido,
      MyAppWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end
```

Keep the namespace fixed once records exist. It is part of every durable record key. See [Instances and Tenants](configuration-and-tenant-isolation.md).

## Configure the instance

Put values that vary by environment in `config/runtime.exs`. The adapter options below are for an Ecto store. See [Persistence Adapters](../storage/persistence-adapters.livemd) to choose one. The ETS adapter loses its data when the BEAM stops, so do not use it for durable production data.

<!-- partial -->
```elixir
import Config

config :my_app, MyApp.Jido,
  persistence: {Jido.Persistence.Ecto, repo: MyApp.Repo},
  agent_server: [
    persistence: :inherit,
    turn_timeout: 30_000,
    max_postponed_signals: 200
  ]
```

Setting `persistence: :inherit` under `:agent_server` makes every Agent in the instance durable. To choose per Agent, leave it out and pass `persistence: :inherit` to `Jido.start_agent/3`.

## Set your limits

Each limit below has a default. Decide on each one, because the right value depends on your Actions and your callers. Use [Load Testing](load-and-performance-testing.md) to find values for your system.

| Option | Default | Effect when reached | Set it from |
| --- | --- | --- | --- |
| `:turn_timeout` | 60,000 ms | The Turn stops with `{:error, :turn_timeout}` and no commit. | The slowest Turn you accept. |
| `:max_postponed_signals` | 1,000 | Callers get `{:error, {:overloaded, details}}`. | How much waiting work one Agent may hold. |
| `:max_directives_per_turn` | 1,000 | The Turn fails with `:too_many_directives` and no commit. | The largest batch a Turn returns. |
| `:directive_timeout` | 5,000 ms | The effects are recorded as timed out. The commit stands. | The slowest delivery batch you accept. |
| `:commit_timeout` | 5,000 ms | Plugin `after_commit/3` work is recorded as timed out. The commit stands. | Your slowest Plugin hook. |
| `:persistence_timeout` | 5,000 ms | The write outcome is uncertain, and the activation stops. | Your store's slowest normal write. |
| `:readiness_timeout` | 5,000 ms | The activation stops. | Plugin startup and composition changes. |
| `:idle_timeout` | `:infinity` | `:idle_policy` runs, which is `:stop` by default. | How long an unused Agent may stay in memory. |

Also set these per call or per Agent when the default does not fit:

- `:admission_timeout` on `Jido.AgentServer.call/3` and `Jido.AgentServer.submit/3`, which defaults to 5,000 ms. See [Admission and Deadlines](../agent-servers/agent-server-admission.md).
- `:exec_opts` on an Agent, for retries and concurrency inside a Turn. See [Execution Policy](../actions/action-execution-policy.md).
- `:error_policy` on an Agent, for its response to failed Turns. The default is `:log_only`. See [Agent Lifecycle](../agent-servers/agent-activation-control.md).

An instance rejects an invalid default at boot.

```elixir
{:error, %Jido.Error.ValidationError{}} =
  Jido.start_link(name: ProductionGuide.Bad, agent_server: [turn_timeout: "30s"])

{:error, %Jido.Error.ValidationError{}} =
  Jido.start_link(name: ProductionGuide.BadStore, agent_server: [persistence: :inherit])
```

## Choose a log level

Jido's semantic logger is off by default. Turn it on so that failures reach your logs.

<!-- partial -->
```elixir
config :jido, :telemetry,
  semantic_log_mode: :errors
```

Failures log at `:warning`. Other events log at `:debug`, so your `Logger` level also has to allow them. [Telemetry and Tracing](telemetry-tracing-and-logs.md#log-modes) describes each mode.

## Export metrics and traces

Pass `Jido.Telemetry.metrics/0` to your metrics reporter. Add `Jido.Telemetry.AI.metrics/0` if you use AI Agents. Jido starts no reporter and no OpenTelemetry SDK. See [Metrics and OTel](metrics-and-open-telemetry.md).

## Activate durable Agents after boot

Jido has no recovery scanner. After a node restart, a durable Agent stays stopped until something activates it, and any Flow Turn it was running stays unfinished until then.

Keep a list of active Agents in your own data. Activate them after your instance starts, with a process that does not block your supervision tree.

<!-- partial -->
```elixir
defmodule MyApp.AgentRecovery do
  use Task, restart: :transient

  def start_link(_arg), do: Task.start_link(__MODULE__, :run, [])

  def run do
    for id <- MyApp.Orders.open_order_ids() do
      {:ok, ref} = Jido.agent_ref(MyApp.Jido, id)

      case Jido.activate_agent(MyApp.Jido, ref, MyApp.OrderAgent) do
        {:ok, _server} -> :ok
        {:error, reason} -> MyApp.Alerts.activation_failed(id, reason)
      end
    end
  end
end
```

Activation is safe to repeat, because `Jido.activate_agent/4` returns the live process when the Agent is already running. A tombstone, an invalid record, or changed Agent code returns an error and does not create new state. See [Durable Agent Activation](../durability/durable-agent-activation.livemd).

Run recovery after an instance restart as well as after a node restart. An instance that restarts comes back with no Agents. Put both children under a `:rest_for_one` supervisor so that a new instance also gets a new recovery run. [Shutdown and Recovery](shutdown-and-recovery.md#restart-agents-with-the-instance) has a full example.

## Drain before you stop

Stopping an instance ends each running Turn with `:indeterminate`. To let work finish, drain from your application's `prep_stop/1` callback. [Shutdown and Recovery](shutdown-and-recovery.md#drain-an-instance) has the code.

## Handle secrets

Reference secrets by name in Plugin options with `Jido.Plugin.Config.env/1`. The Agent definition and its snapshots keep only the variable name, and the Plugin reads the value when its runtime starts. Do not put secrets in Agent state or Signal data. See [Security Model](security.md).

## Application environment

These settings apply to the whole node. Set them under `config :jido`.

| Key | Default | Effect |
| --- | --- | --- |
| `Jido.AgentServer`, `turn_timeout:` | 60,000 ms | The default for Agents with no other `:turn_timeout`. Any other key under `Jido.AgentServer` makes Agent starts fail. |
| `:telemetry`, `semantic_log_mode:` | `:off` | `:off`, `:errors`, `:interesting`, or `:all`. |
| `:telemetry`, `semantic_slow_threshold_ms:` | 1,000 | The duration that `:interesting` reports as slow. |
| `:ai_telemetry` | See `Jido.Telemetry.AI` | The same log settings for AI events, and correlation retention. |
| `:opentelemetry`, `enabled:` | Unset | `false` turns off the Jido span mapping. |
| `:ai_opentelemetry`, `enabled:` | Unset | `false` turns off the AI span mapping. |
| `:max_concurrency` | Schedulers online, at most 10 | The default concurrency for direct `Jido.Exec` calls. An AgentServer Turn uses its own `:exec_opts`. |
| `:max_payload_bytes` | 10,000,000 | The `Jido.Signal.Codec` size limit. |
| `Jido.Codec`, `maximum_json_bytes:` | 8,388,608 | The `Jido.Codec` JSON size limit. |
| `Jido.Signal.Bus`, `call_timeout:` | 30,000 ms | The wait for a call to a `Jido.Signal.Bus`. |

## Check before you ship

- The namespace is set and final, and the instance starts after its dependencies.
- The adapter keeps data outside the BEAM, and you have tested a restart against it.
- Each limit in the table above has a value you chose or accepted.
- `semantic_log_mode` is on, and failures reach your log system.
- A reporter receives `Jido.Telemetry.metrics/0`, with alerts on Turn and effect failures.
- Your application knows which durable Agents to activate at boot.
- Your release drains before it stops, and your platform's stop timeout allows for that.

## Next steps

- [Deployment and Sizing](deployment-and-performance.md)
- [Shutdown and Recovery](shutdown-and-recovery.md)
- [Security Model](security.md)
