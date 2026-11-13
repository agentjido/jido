defmodule Jido.Examples.Capabilities.SensorManager.Agent do
  @moduledoc "Owns a tagged reading sensor through Sensor Manager Directives."

  use Jido.Agent,
    name: "examples_capabilities_sensor_manager_agent",
    plugins: [{Jido.Plugin.SensorManager, %{retry_delay_ms: 10}}]

  alias Jido.Examples.Capabilities.SensorManager.ReadingSensor
  alias Jido.Plugin.SensorManager

  state do
    schema Jido.Joi.object(%{
             readings: Jido.Joi.list(Jido.Joi.map()) |> Jido.Joi.default([])
           })
  end

  routes do
    signal_source "/examples/capabilities/sensor_manager"

    route "examples.capabilities.sensor_manager.start", as: :start_sensor do
      action %{multiplier: multiplier, tag: tag},
        schema:
          Jido.Joi.object(%{
            multiplier: Jido.Joi.integer(),
            tag: Jido.Joi.string() |> Jido.Joi.min(1)
          }),
        context: context do
        directive =
          SensorManager.start(tag, ReadingSensor, %{
            multiplier: multiplier,
            source: "/examples/capabilities/sensor_manager/#{tag}"
          })

        {:ok, context.agent_state, [directive]}
      end
    end

    route "examples.capabilities.sensor_manager.stop", as: :stop_sensor do
      action %{tag: tag},
        schema: Jido.Joi.object(%{tag: Jido.Joi.string() |> Jido.Joi.min(1)}),
        context: context do
        {:ok, context.agent_state, [SensorManager.stop(tag)]}
      end
    end

    route "examples.capabilities.sensor_manager.reading" do
      action reading,
        schema:
          Jido.Joi.object(%{
            tag: Jido.Joi.string() |> Jido.Joi.min(1),
            value: Jido.Joi.integer()
          }),
        context: context do
        {:ok, %{context.agent_state | readings: context.agent_state.readings ++ [reading]}}
      end
    end
  end
end

defmodule Jido.Examples.Capabilities.SensorManager.ReadingSensor do
  @moduledoc "Translates local readings into normal Agent Signals."

  use GenServer

  alias Jido.AgentServer
  alias Jido.Plugin.SensorManager.Init

  def start_link(%Init{} = init) do
    GenServer.start_link(__MODULE__, init, name: via(init.agent_id, init.tag))
  end

  @doc "Returns the sensor process for one Agent and tag."
  @spec whereis(String.t(), term()) :: pid() | nil
  def whereis(agent_id, tag) do
    case :global.whereis_name(name(agent_id, tag)) do
      pid when is_pid(pid) -> pid
      :undefined -> nil
    end
  end

  @doc "Adds one reading to the owning Agent through the sensor."
  @spec push(pid(), integer()) :: :ok
  def push(sensor, value), do: GenServer.cast(sensor, {:push, value})

  @impl true
  def init(%Init{} = init), do: {:ok, init}

  @impl true
  def handle_cast({:push, value}, %Init{} = init) do
    signal =
      Jido.Signal.new!(
        "examples.capabilities.sensor_manager.reading",
        %{tag: init.tag, value: value * init.config.multiplier},
        source: init.config.source
      )

    AgentServer.cast(init.agent_server, signal)
    {:noreply, init}
  end

  defp via(agent_id, tag), do: {:global, name(agent_id, tag)}
  defp name(agent_id, tag), do: {__MODULE__, agent_id, tag}
end
