defmodule Jido.Examples.Applications.BusInput do
  @moduledoc false

  use Jido.Plugin

  alias Jido.Plugin.Init
  alias Jido.Examples.Applications.BusInput.Runtime

  @doc false
  def child_spec(%Init{} = init) do
    Supervisor.child_spec({Runtime, init}, id: __MODULE__)
  end
end

defmodule Jido.Examples.Applications.BusInput.Runtime do
  @moduledoc false

  use GenServer

  alias Jido.AgentServer, as: Server
  alias Jido.Plugin.Init
  alias Jido.Signal.Bus

  def start_link(%Init{} = init), do: GenServer.start_link(__MODULE__, init)

  @impl true
  def init(%Init{} = init) do
    state = %{
      agent_server: init.agent_server,
      jido: init.jido,
      bus_name: Keyword.fetch!(init.options, :bus),
      paths: Keyword.fetch!(init.options, :paths),
      bus: nil,
      subscriptions: []
    }

    {:ok, state, {:continue, :subscribe}}
  end

  @impl true
  def handle_continue(:subscribe, state) do
    with {:ok, bus} <- Bus.whereis(state.bus_name, jido: state.jido),
         {:ok, subscriptions} <- subscribe_all(bus, state.paths) do
      {:noreply, %{state | bus: bus, subscriptions: subscriptions}}
    else
      {:error, reason} -> {:stop, {:bus_input_attach_failed, reason}, state}
    end
  end

  @impl true
  def handle_call(:await_ready, _from, state), do: {:reply, :ok, state}

  @impl true
  def handle_info({:signal, signal}, state) do
    Server.cast(state.agent_server, signal)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.subscriptions, fn subscription_id ->
      _ = Bus.unsubscribe(state.bus, subscription_id)
    end)

    :ok
  end

  defp subscribe_all(bus, paths) when is_list(paths) do
    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, subscriptions} ->
      case Bus.subscribe(bus, path, target: self()) do
        {:ok, subscription_id} ->
          {:cont, {:ok, [subscription_id | subscriptions]}}

        {:error, reason} ->
          Enum.each(subscriptions, &Bus.unsubscribe(bus, &1))
          {:halt, {:error, reason}}
      end
    end)
  end
end
