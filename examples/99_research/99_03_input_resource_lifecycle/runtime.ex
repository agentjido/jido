defmodule Jido.Examples.RuntimeReconstruction.Runtime do
  @moduledoc "Builds and replaces one disposable feed resource from committed Plugin state."
  use GenServer

  def start_link(init), do: GenServer.start_link(__MODULE__, init)
  def inspect_runtime(pid), do: GenServer.call(pid, :inspect)
  def input(pid, feed, text), do: GenServer.call(pid, {:input, feed, text})

  @impl true
  def init(init),
    do: {:ok, open_resource(%{init: init, resource: nil, feed: nil}, init.plugin_state.name)}

  @impl true
  def handle_call(:reconcile, _from, state) do
    case reconcile(state) do
      {:ok, next} -> {:reply, :ok, next}
      error -> {:reply, error, state}
    end
  end

  def handle_call(:inspect, _from, state), do: {:reply, state, state}

  def handle_call({:input, feed, text}, _from, %{feed: feed} = state) do
    signal =
      Jido.Signal.new!(
        "examples.research.runtime_reconstruction.feed.input",
        %{feed: feed, text: text},
        source: "/examples/research/runtime_reconstruction/runtime"
      )

    {:reply, Jido.AgentServer.cast(state.init.agent_server, signal), state}
  end

  def handle_call({:input, _feed, _text}, _from, state),
    do: {:reply, {:error, :stale_feed}, state}

  @impl true
  def terminate(_reason, state), do: stop_resource(state.resource)

  defp reconcile(state) do
    with {:ok, %{name: feed}} <- Jido.Plugin.state(state.init) do
      stop_resource(state.resource)
      {:ok, open_resource(state, feed)}
    end
  end

  defp open_resource(state, feed) do
    resource =
      spawn_link(fn ->
        receive do
          :close -> :ok
        end
      end)

    %{state | resource: resource, feed: feed}
  end

  defp stop_resource(nil), do: :ok

  defp stop_resource(pid) do
    ref = Process.monitor(pid)
    send(pid, :close)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      1_000 -> Process.demonitor(ref, [:flush])
    end
  end
end
