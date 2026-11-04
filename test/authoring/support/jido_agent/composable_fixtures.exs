defmodule Jido.Test.Agent.Authoring.Action do
  use Jido.Action,
    name: "agent_authoring_action",
    schema: Jido.Joi.object(%{value: Jido.Joi.string()})

  def run(_, _), do: raise("Authoring must not run Actions")
end

defmodule Jido.Test.Agent.Authoring.Flow do
  use Jido.Flow,
    name: "agent_authoring_flow",
    schema: Jido.Joi.object(%{value: Jido.Joi.string()})

  flow do
    step "work", action: Jido.Test.Agent.Authoring.Action, params: %{value: input(:value)}
    output result("work")
  end
end

defmodule Jido.Test.Agent.Authoring.Adapter do
  def normalize(_signal), do: raise("Authoring must not call transforms")
end

defmodule Jido.Test.Agent.Authoring.Worker do
  use Jido.Agent, name: "worker"

  state do
    schema Jido.Joi.object(%{value: Jido.Joi.string() |> Jido.Joi.default("")})
  end

  routes do
    signal_source "/worker"

    route "work.request", Jido.Test.Agent.Authoring.Action

    route "plan.request", Jido.Test.Agent.Authoring.Flow
  end
end

defmodule Jido.Test.Agent.Authoring.Team do
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
    schema Jido.Joi.object(%{
             value: Jido.Joi.string() |> Jido.Joi.default("input"),
             workers: Jido.Joi.integer() |> Jido.Joi.default(2)
           })
  end

  routes do
    signal_source "/team"

    route "work.request", Jido.Test.Agent.Authoring.Action, as: :request

    route "plan.request", Jido.Test.Agent.Authoring.Action, as: :plan

    route "work.done", Jido.Test.Agent.Authoring.Action, defaults: %{value: "done"}

    route "flow.request", Jido.Test.Agent.Authoring.Flow

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
        schema: Jido.Joi.object(%{value: Jido.Joi.string()}),
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

    route "unknown.request", Jido.Test.Agent.Authoring.Action
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
    agent :planner, Jido.Test.Agent.Authoring.Worker do
      initial_state %{value: state(:value)}
    end

    agent :workers, Jido.Test.Agent.Authoring.Worker do
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

defmodule Jido.Test.Agent.Authoring.Audit do
  alias Jido.Agent.Schema
  alias Spark.Dsl.Extension, as: SparkExtension

  @section %Spark.Dsl.Section{name: :audit, schema: [label: [type: :string, required: true]]}
  use Jido.Plugin, id: "test.audit", sections: [@section]

  def lower(dsl, config) do
    label = SparkExtension.get_opt(dsl, [:audit], :label)
    if label, do: {:ok, Map.put(config, :label, label)}, else: {:ok, config}
  end

  def normalize(data) do
    with {:ok, data} <- Schema.fields(data, [:label, :enabled], %{enabled: true}),
         :ok <- Schema.nonempty(data[:label]),
         do: {:ok, data}
  end
end

defmodule Jido.Test.Agent.Authoring.PluginFirst do
  use Jido.Agent,
    name: "plugin",
    plugins: [{Jido.Test.Agent.Authoring.Audit, %{enabled: false}}]

  audit do
    label("example")
  end
end

defmodule Jido.Test.Agent.Authoring.PluginLast do
  use Jido.Agent,
    name: "plugin",
    plugins: [{Jido.Test.Agent.Authoring.Audit, %{enabled: false}}]

  audit do
    label("example")
  end
end

defmodule Jido.Test.Agent.Authoring.Minimal do
  use Jido.Agent, name: "minimal"
end

defmodule Jido.Test.Agent.Authoring.Named do
  use Jido.Agent,
    name: "named",
    description: "Named executables",
    vsn: 3,
    metadata: %{label: "named"}

  state do
    schema Jido.Joi.object(%{value: Jido.Joi.string() |> Jido.Joi.default("initial")})
  end

  routes do
    signal_source "/named"

    route "work.request", Jido.Test.Agent.Authoring.Action,
      as: :work,
      defaults: %{value: "default"} do
    end

    route "plan.request", Jido.Test.Agent.Authoring.Flow

    route "pass.request", Jido.Test.Agent.Authoring.Action, as: :pass

    route "work.*", Jido.Test.Agent.Authoring.Action
  end
end

defmodule Jido.Test.Agent.Authoring.ScheduleShort do
  use Jido.Agent, name: "schedule", plugins: [Jido.Plugin.Scheduler.DSL]

  routes do
    route "work.request", Jido.Test.Agent.Authoring.Action
  end

  schedules do
    schedule :review, every: 60_000, signal: %{type: "work.request"}

    schedule :refresh,
      cron: "*/5 * * * *",
      signal: %{type: "work.request", data: %{value: "refresh"}}
  end
end

defmodule Jido.Test.Agent.Authoring.ScheduleBlock do
  use Jido.Agent, name: "schedule", plugins: [Jido.Plugin.Scheduler.DSL]

  routes do
    route "work.request", Jido.Test.Agent.Authoring.Action
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

defmodule Jido.Test.Agent.Authoring.PluginAlias do
  use Jido.Agent,
    name: "plugin",
    plugins: [{Jido.Test.Agent.Authoring.Audit, %{enabled: false}}]

  alias Jido.Test.Agent.Authoring.Action

  audit do
    label("example")
  end

  routes do
    route "work.request", Action
  end
end

defmodule Jido.Test.Agent.Authoring.OwnedPlugin do
  use Jido.Plugin, id: "test.owned", vsn: 2

  @impl Jido.Plugin
  def state_spec(opts), do: {:owned, Jido.Joi.integer() |> Jido.Joi.default(Keyword.get(opts, :initial, 1))}

  @impl Jido.Plugin
  def prepare(_, _), do: raise("authoring must not prepare a runtime input")
end

defmodule Jido.Test.Agent.Authoring.ConflictingPlugin do
  use Jido.Plugin, id: "test.conflict"
  @impl Jido.Plugin
  def state_spec(_), do: {:owned, Jido.Joi.integer() |> Jido.Joi.default(0)}
end

defmodule Jido.Test.Agent.Authoring.PluginState do
  use Jido.Agent,
    name: "plugin_state",
    plugins: [{Jido.Test.Agent.Authoring.OwnedPlugin, %{initial: 3}}]

  state do
    schema Jido.Joi.object(%{value: Jido.Joi.string() |> Jido.Joi.default("domain")})
  end
end
