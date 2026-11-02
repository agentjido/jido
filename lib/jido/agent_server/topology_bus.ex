defmodule Jido.AgentServer.TopologyBus do
  @moduledoc false
  use GenServer
  alias Jido.AgentServer.TopologyRuntime
  alias Jido.Signal.Bus

  def start_link(args), do: GenServer.start_link(__MODULE__, args)

  def reconcile(data) do
    names = TopologyRuntime.buses(data.agent)
    existing = if data.activation, do: Supervisor.which_children(data.activation), else: []

    Enum.each(existing, fn
      {{:topology_bus, name} = id, _, _, _} ->
        if name not in names do
          :ok = Supervisor.terminate_child(data.activation, id)
          :ok = Supervisor.delete_child(data.activation, id)
          :ets.delete(data.activation_state, {:topology_bus, name})
        end

      _ ->
        :ok
    end)

    Enum.reduce_while(names, :ok, fn name, :ok ->
      id = {:topology_bus, name}

      if List.keymember?(existing, id, 0) do
        {:cont, :ok}
      else
        context = %{
          state: data.activation_state,
          jido: data.jido,
          partition: data.partition,
          agent_id: data.agent.id
        }

        spec = %{id: id, start: {__MODULE__, :start_link, [{context, name}]}}

        case Supervisor.start_child(data.activation, spec) do
          {:ok, _} -> {:cont, :ok}
          error -> {:halt, error}
        end
      end
    end)
  end

  @impl true
  def init({context, name}) do
    bus_name =
      "$agent/" <>
        Base.url_encode64(:erlang.term_to_binary({context.partition, context.agent_id, name}),
          padding: false
        )

    with {:ok, bus} <- Bus.start_link(name: bus_name, jido: context.jido),
         {:ok, _subscription} <- Bus.subscribe(bus, "**") do
      owner = :ets.lookup_element(context.state, :worker, 2)
      :ets.insert(context.state, {{:topology_bus, name}, bus})
      {:ok, %{owner: owner, name: name, bus: bus}}
    end
  end

  @impl true
  def handle_info({:signal, signal}, state) do
    :gen_statem.cast(state.owner, {:topology_bus, state.name, signal})
    {:noreply, state}
  end

  def publish(state, name, signal) do
    case :ets.lookup(state, {:topology_bus, name}) do
      [{_, bus}] ->
        case Bus.publish(bus, [signal]) do
          {:ok, _} -> :ok
          error -> error
        end

      [] ->
        {:error, :bus_not_ready}
    end
  end
end
