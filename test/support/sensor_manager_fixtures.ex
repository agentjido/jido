defmodule JidoTest.Plugin.SensorManagerFixtures do
  @moduledoc false

  defmodule EmittingSensor do
    @moduledoc false

    use GenServer

    alias Jido.AgentServer
    alias Jido.Plugin.SensorManager.Init
    alias Jido.Signal

    def start_link(%Init{} = init), do: GenServer.start_link(__MODULE__, init)

    @impl true
    def init(%Init{} = init) do
      signal = Signal.new!("sensor.reading", %{value: init.config.value}, source: "/sensor/test")
      AgentServer.cast(init.agent_server, signal)
      {:ok, init}
    end
  end

  defmodule ControlledSensor do
    @moduledoc false

    use GenServer

    alias Jido.Plugin.SensorManager.Init

    def child_spec(%Init{config: %{failure: :raise}}), do: raise("invalid sensor spec")
    def child_spec(%Init{config: %{failure: :throw}}), do: throw(:invalid_sensor_spec)
    def child_spec(init), do: super(init)

    def start_link(%Init{config: %{gate: gate}} = init) do
      case Elixir.Agent.get_and_update(gate, fn
             [result | rest] -> {result, rest}
             [] -> {:ok, []}
           end) do
        :ok ->
          GenServer.start_link(__MODULE__, init)

        :with_info ->
          {:ok, pid} = GenServer.start_link(__MODULE__, init)
          {:ok, pid, :sensor_info}

        :ignore ->
          :ignore

        {:error, reason} ->
          {:error, reason}
      end
    end

    @impl true
    def init(init), do: {:ok, init}
  end

  defmodule ManageAction do
    @moduledoc false

    use Jido.Action, name: "sensor_manager_manage"

    alias Jido.Plugin.SensorManager
    alias JidoTest.Plugin.SensorManagerFixtures.EmittingSensor

    @impl Jido.Action
    def run(%{operation: :start, value: value}, context) do
      directives = [SensorManager.start(:source, EmittingSensor, %{value: value})]
      {:ok, context.agent_state, directives}
    end

    def run(%{operation: :stop}, context) do
      {:ok, context.agent_state, [SensorManager.stop(:source)]}
    end
  end

  defmodule ReadingAction do
    @moduledoc false

    use Jido.Action, name: "sensor_manager_reading"

    @impl Jido.Action
    def run(%{value: value}, context) do
      readings = context.agent_state.readings ++ [value]
      {:ok, %{context.agent_state | readings: readings}}
    end
  end

  defmodule Agent do
    @moduledoc false

    use Jido.Agent,
      name: "sensor_manager_contract_agent",
      plugins: [{Jido.Plugin.SensorManager, %{retry_delay_ms: 10}}]

    alias Jido.Plugin.SensorManager
    alias JidoTest.Plugin.SensorManagerFixtures.{ManageAction, ReadingAction}

    state do
      schema Zoi.object(%{readings: Zoi.list(Zoi.integer()) |> Zoi.default([])})
    end

    routes do
      route "sensor.manage", ManageAction
      route "sensor.reading", ReadingAction
    end
  end

  def child_pid(supervisor, id) do
    supervisor
    |> Supervisor.which_children()
    |> Enum.find_value(fn
      {^id, pid, _type, _modules} when is_pid(pid) -> pid
      _child -> nil
    end)
  end
end
