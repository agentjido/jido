defmodule JidoTest.Plugin.BusFixtures do
  @moduledoc false

  defmodule RecordAction do
    @moduledoc false
    use Jido.Action, name: "bus_plugin_record"

    @impl Jido.Action
    def run(%{value: value}, context) do
      {:ok, %{context.agent_state | values: context.agent_state.values ++ [value]}}
    end
  end

  defmodule RetryAction do
    @moduledoc false
    use Jido.Action, name: "bus_plugin_retry"

    @impl Jido.Action
    def run(%{value: value}, context) do
      attempt = :ets.update_counter(:jido_bus_plugin_attempts, :attempt, 1)

      if attempt == 1,
        do: {:error, :simulated_failure},
        else: {:ok, %{context.agent_state | values: context.agent_state.values ++ [value]}}
    end
  end

  defmodule BlockingRecordAction do
    @moduledoc false
    use Jido.Action, name: "bus_plugin_blocking_record"

    @impl Jido.Action
    def run(%{value: value, observer: observer, gate: gate}, context) do
      send(observer, {:bus_turn_blocked, value, self()})

      receive do
        {:release, ^gate} ->
          {:ok, %{context.agent_state | values: context.agent_state.values ++ [value]}}
      end
    end
  end

  defmodule ClientAgent do
    @moduledoc false
    use Jido.Agent, name: "bus_plugin_agent"

    state do
      schema Zoi.object(%{values: Zoi.list(Zoi.integer()) |> Zoi.default([])})
    end

    plugins do
      plugin Jido.Plugin.Bus.Client, config: %{bus: :plugin_bus, path: "bus.**"}
    end

    routes do
      route "bus.input", JidoTest.Plugin.BusFixtures.RecordAction
    end
  end

  defmodule DurableAgent do
    @moduledoc false
    use Jido.Agent, name: "durable_bus_plugin_agent"

    state do
      schema Zoi.object(%{values: Zoi.list(Zoi.integer()) |> Zoi.default([])})
    end

    plugins do
      plugin Jido.Plugin.Bus.Client,
        config: %{
          bus: :plugin_bus,
          path: "bus.**",
          durable: "durable-bus-agent",
          start_from: :origin,
          retry_delay_ms: 10
        }
    end

    routes do
      route "bus.input", JidoTest.Plugin.BusFixtures.RecordAction
      route "bus.retry", JidoTest.Plugin.BusFixtures.RetryAction
    end
  end

  defmodule DurableBlockingAgent do
    @moduledoc false
    use Jido.Agent, name: "durable_blocking_bus_plugin_agent"

    state do
      schema Zoi.object(%{values: Zoi.list(Zoi.integer()) |> Zoi.default([])})
    end

    plugins do
      plugin Jido.Plugin.Bus.Client,
        config: %{
          bus: :plugin_bus,
          path: "bus.**",
          durable: "durable-bus-barrier",
          start_from: :origin,
          retry_delay_ms: 10
        }
    end

    routes do
      route "bus.block", JidoTest.Plugin.BusFixtures.BlockingRecordAction
    end
  end

  defmodule ManagerAgent do
    @moduledoc false
    use Jido.Agent, name: "bus_manager_agent"

    plugins do
      plugin Jido.Plugin.Bus.Manager
    end
  end

  defmodule OwnedBusAgent do
    @moduledoc false
    use Jido.Agent, name: "owned_bus_agent"

    state do
      schema Zoi.object(%{values: Zoi.list(Zoi.integer()) |> Zoi.default([])})
    end

    plugins do
      plugin Jido.Plugin.Bus.Manager, config: %{name: :owned_plugin_bus}

      plugin Jido.Plugin.Bus.Client,
        config: %{bus: :owned_plugin_bus, path: "bus.**", retry_delay_ms: 10}
    end

    routes do
      route "bus.input", JidoTest.Plugin.BusFixtures.RecordAction
    end
  end

  defmodule AckBus do
    @moduledoc false
    use GenServer

    def start_link({owner, replies}), do: GenServer.start_link(__MODULE__, {owner, replies})

    @impl true
    def init({owner, replies}), do: {:ok, %{owner: owner, replies: replies}}

    @impl true
    def handle_call({:ack, durable_id, cursor}, _from, %{replies: [reply | rest]} = state) do
      send(state.owner, {:bus_ack, durable_id, cursor, reply})
      {:reply, reply, %{state | replies: rest}}
    end
  end
end
