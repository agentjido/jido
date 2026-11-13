defmodule Jido.Examples.Plugins.RuntimeResource.Inspect do
  @moduledoc "Requests one post-commit report from the Plugin runtime."
  use Jido.Agent.Directive

  @schema Jido.Joi.struct(
            __MODULE__,
            %{label: Jido.Joi.string() |> Jido.Joi.min(1)},
            coerce: true
          )

  @enforce_keys Jido.Joi.enforce_keys(@schema)
  defstruct Jido.Joi.struct_fields(@schema)
  def schema, do: @schema
end

defmodule Jido.Examples.Plugins.RuntimeResource.Runtime do
  @moduledoc "A supervised Plugin root that owns one activation-local resource."
  use GenServer

  alias Jido.Plugin.Init

  def start_link(%Init{} = init), do: GenServer.start_link(__MODULE__, init)

  def report(runtime), do: GenServer.call(runtime, :report)

  @impl true
  def init(%Init{} = init) do
    {:ok, resource} = Agent.start_link(fn -> %{started_at_revision: init.state_version} end)
    {:ok, %{init: init, resource: resource}}
  end

  @impl true
  def handle_call(:report, _from, state) do
    report = %{
      runtime: self(),
      resource: state.resource,
      agent_id: state.init.agent_id,
      started_at_revision: Agent.get(state.resource, & &1.started_at_revision)
    }

    {:reply, report, state}
  end
end

defmodule Jido.Examples.Plugins.RuntimeResource.Plugin do
  @moduledoc "Owns one Directive and one supervised runtime root."

  use Jido.Plugin, option_keys: [agent_server: [:observer]]

  alias Jido.Examples.Plugins.RuntimeResource.{Inspect, Runtime}
  alias Jido.Plugin.Init

  @impl true
  def directives(_opts), do: [Inspect]

  @impl true
  def child_spec(%Init{} = init),
    do: Supervisor.child_spec({Runtime, init}, id: __MODULE__)

  @impl true
  def await_ready(runtime, _opts) do
    %{runtime: ^runtime} = Runtime.report(runtime)
    :ok
  end

  @impl true
  def dispatch(runtime, %Inspect{label: label}, context, opts) do
    report = Runtime.report(runtime)

    send(Keyword.fetch!(opts, :observer), {
      :runtime_report,
      label,
      context.state_version,
      report
    })

    :ok
  end
end

defmodule Jido.Examples.Plugins.RuntimeResource.Agent do
  @moduledoc "Uses a Directive to contact its Plugin-owned runtime after commit."

  use Jido.Agent,
    name: "plugin_runtime_resource",
    plugins: [Jido.Examples.Plugins.RuntimeResource.Plugin]

  alias Jido.Examples.Plugins.RuntimeResource.Inspect

  state do
    schema Jido.Joi.object(%{requests: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/examples/plugins/runtime-resource"

    route "examples.plugins.runtime_resource.inspect", as: :inspect_runtime do
      action %{label: label},
        schema: Jido.Joi.object(%{label: Jido.Joi.string() |> Jido.Joi.min(1)}),
        context: context do
        {:ok, %{context.agent_state | requests: context.agent_state.requests + 1}, [%Inspect{label: label}]}
      end
    end
  end
end
