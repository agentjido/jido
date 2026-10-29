defmodule JidoTest.ComposableAgent.Action do
  use Jido.Action,
    name: "agent_authoring_action",
    schema: Zoi.object(%{value: Zoi.string()})

  def run(_, _), do: raise("Authoring must not run Actions")
end

defmodule JidoTest.ComposableAgent.Flow do
  use Jido.Flow,
    name: "agent_authoring_flow",
    schema: Zoi.object(%{value: Zoi.string()})

  flow do
    step "work", action: JidoTest.ComposableAgent.Action, params: %{value: input(:value)}
    output result("work")
  end
end

defmodule JidoTest.ComposableAgent.Adapter do
  def normalize(_signal), do: raise("Authoring must not call transforms")
end

defmodule JidoTest.ComposableAgent.Worker do
  use Jido.Agent, name: "worker"

  state do
    schema Zoi.object(%{value: Zoi.string() |> Zoi.default("")})
  end

  routes do
    signal_source "/worker"

    route "work.request", JidoTest.ComposableAgent.Action

    route "plan.request", JidoTest.ComposableAgent.Flow
  end
end

defmodule JidoTest.ComposableAgent.Team do
  use Jido.Agent,
    name: "team",
    description: "Test team",
    vsn: 2,
    metadata: %{label: "team"},
    plugins: [
      Jido.Plugin.Scheduler.DSL,
      Jido.Plugin.Bus.DSL
    ]

  state do
    schema Zoi.object(%{
             value: Zoi.string() |> Zoi.default("input"),
             workers: Zoi.integer() |> Zoi.default(2)
           })
  end

  routes do
    signal_source "/team"

    route "work.request", JidoTest.ComposableAgent.Action, as: :request

    route "plan.request", JidoTest.ComposableAgent.Action, as: :plan

    route "work.done", JidoTest.ComposableAgent.Action, defaults: %{value: "done"}

    route "flow.request", JidoTest.ComposableAgent.Flow

    route "external.request" do
      transform signal do
        {:ok, %{signal | type: "work.request"}}
      end
    end

    route "external.clauses" do
      transform do
        %Jido.Signal{data: %{value: value}} = signal when is_binary(value) ->
          {:ok, %{signal | type: "work.request", data: %{value: String.trim(value)}}}

        %Jido.Signal{data: %{"value" => value}} = signal when is_binary(value) ->
          {:ok, %{signal | type: "work.request", data: %{value: value}}}

        _ ->
          {:error, :invalid_value}
      end
    end

    route "inline.request" do
      action %{value: _value},
        schema: Zoi.object(%{value: Zoi.string()}),
        context: context do
        {:ok, context.agent_state}
      end
    end

    route "inline.emit" do
      action _params, context: context do
        {:ok, context.agent_state, [emit("team.done", %{})]}
      end
    end

    route "partial.request" do
      transform %Jido.Signal{data: %{value: value}} = signal when is_binary(value) do
        {:ok, %{signal | type: "work.request"}}
      end
    end

    route "unknown.request", JidoTest.ComposableAgent.Action
  end

  schedules do
    schedule :review do
      every(60_000)
      signal(%{type: "plan.request", data: %{value: "review"}})
    end

    schedule :refresh,
      cron: "*/5 * * * *",
      signal: %{type: "work.request", data: %{value: "refresh"}}
  end

  signal_bus do
    name(:events)
  end

  topology do
    agent :planner, JidoTest.ComposableAgent.Worker do
      initial_state %{value: state(:value)}
    end

    agent :workers, JidoTest.ComposableAgent.Worker do
      count state(:workers)
      initial_state %{value: state(:value)}
    end

    connections do
      connect("plan.request", from: :root, to: bus(:events))
      connect("plan.request", from: bus(:events), to: :planner)
      connect("work.request", from: :root, to: bus(:events))
      connect("work.request", from: :planner, to: bus(:events))
      connect("work.request", from: bus(:events), to: :workers, delivery: :broadcast)
      connect("work.done", from: :workers, to: :root)
    end
  end
end

defmodule JidoTest.ComposableAgent.Audit do
  alias Jido.Agent.Data
  alias Spark.Dsl.Extension, as: SparkExtension

  @section %Spark.Dsl.Section{name: :audit, schema: [label: [type: :string, required: true]]}
  use Jido.Plugin, id: "test.audit", sections: [@section]

  def lower(dsl, config) do
    label = SparkExtension.get_opt(dsl, [:audit], :label)
    if label, do: {:ok, Map.put(config, :label, label)}, else: {:ok, config}
  end

  def normalize(data) do
    with {:ok, data} <- Data.fields(data, [:label, :enabled], %{enabled: true}),
         :ok <- Data.nonempty(data[:label]),
         do: {:ok, data}
  end
end

defmodule JidoTest.ComposableAgent.PluginFirst do
  use Jido.Agent,
    name: "plugin",
    plugins: [{JidoTest.ComposableAgent.Audit, %{enabled: false}}]

  audit do
    label("example")
  end
end

defmodule JidoTest.ComposableAgent.PluginLast do
  use Jido.Agent,
    name: "plugin",
    plugins: [{JidoTest.ComposableAgent.Audit, %{enabled: false}}]

  audit do
    label("example")
  end
end

defmodule JidoTest.ComposableAgent.Minimal do
  use Jido.Agent, name: "minimal"
end

defmodule JidoTest.ComposableAgent.Named do
  use Jido.Agent,
    name: "named",
    description: "Named executables",
    vsn: 3,
    metadata: %{label: "named"}

  state do
    schema Zoi.object(%{value: Zoi.string() |> Zoi.default("initial")})
  end

  routes do
    signal_source "/named"

    route "work.request", JidoTest.ComposableAgent.Action,
      as: :work,
      defaults: %{value: "default"} do
    end

    route "plan.request", JidoTest.ComposableAgent.Flow

    route "pass.request", JidoTest.ComposableAgent.Action, as: :pass

    route "work.*", JidoTest.ComposableAgent.Action
  end
end

defmodule JidoTest.ComposableAgent.ScheduleShort do
  use Jido.Agent, name: "schedule", plugins: [Jido.Plugin.Scheduler.DSL]

  routes do
    route "work.request", JidoTest.ComposableAgent.Action
  end

  schedules do
    schedule :review, every: 60_000, signal: %{type: "work.request"}

    schedule :refresh,
      cron: "*/5 * * * *",
      signal: %{type: "work.request", data: %{value: "refresh"}}
  end
end

defmodule JidoTest.ComposableAgent.ScheduleBlock do
  use Jido.Agent, name: "schedule", plugins: [Jido.Plugin.Scheduler.DSL]

  routes do
    route "work.request", JidoTest.ComposableAgent.Action
  end

  schedules do
    schedule :review do
      every(60_000)
      signal(%{type: "work.request", data: %{}})
    end

    schedule :refresh do
      cron("*/5 * * * *")
      timezone("Etc/UTC")
      signal(%{type: "work.request", data: %{value: "refresh"}})
    end
  end
end

defmodule JidoTest.ComposableAgent.PluginAlias do
  use Jido.Agent,
    name: "plugin",
    plugins: [{JidoTest.ComposableAgent.Audit, %{enabled: false}}]

  alias JidoTest.ComposableAgent.Action

  audit do
    label("example")
  end

  routes do
    route "work.request", Action
  end
end

defmodule JidoTest.ComposableAgent.OwnedPlugin do
  use Jido.Plugin, id: "test.owned", vsn: 2

  @impl Jido.Plugin
  def state_spec(opts), do: {:owned, Zoi.integer() |> Zoi.default(Keyword.get(opts, :initial, 1))}

  @impl Jido.Plugin
  def prepare(_, _), do: raise("authoring must not prepare a runtime input")
end

defmodule JidoTest.ComposableAgent.ConflictingPlugin do
  use Jido.Plugin, id: "test.conflict"
  @impl Jido.Plugin
  def state_spec(_), do: {:owned, Zoi.integer() |> Zoi.default(0)}
end

defmodule JidoTest.ComposableAgent.PluginState do
  use Jido.Agent,
    name: "plugin_state",
    plugins: [{JidoTest.ComposableAgent.OwnedPlugin, %{initial: 3}}]

  state do
    schema Zoi.object(%{value: Zoi.string() |> Zoi.default("domain")})
  end
end
