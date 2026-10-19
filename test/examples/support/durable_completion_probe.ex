defmodule JidoTest.Examples.Durable.CompletionProbe do
  @moduledoc false
  use GenServer

  def start_link(observer), do: GenServer.start_link(__MODULE__, observer, name: __MODULE__)
  def completed, do: GenServer.call(__MODULE__, :completed)
  def count, do: GenServer.call(__MODULE__, :count)
  def saved, do: GenServer.call(__MODULE__, :saved, :infinity)
  def release, do: GenServer.call(__MODULE__, :release)

  def init(observer), do: {:ok, %{observer: observer, count: 0, held?: false, waiter: nil}}
  def handle_call(:completed, _, state), do: {:reply, :ok, %{state | count: state.count + 1}}
  def handle_call(:count, _, state), do: {:reply, state.count, state}

  def handle_call(:saved, from, %{held?: false} = state) do
    send(state.observer, {:completion_saved, elem(from, 0)})
    {:noreply, %{state | held?: true, waiter: from}}
  end

  def handle_call(:saved, _, state), do: {:reply, :ok, state}

  def handle_call(:release, _, state) do
    if state.waiter, do: GenServer.reply(state.waiter, :ok)
    {:reply, :ok, %{state | waiter: nil}}
  end
end

defmodule JidoTest.Examples.Durable.CompletionStorage do
  @moduledoc false
  @behaviour Jido.Persistence.Adapter
  alias JidoTest.Examples.Durable.CompletionProbe

  def get(key, opts), do: Jido.Persistence.File.get(key, opts)

  def compare_and_swap(key, expected, bytes, opts) do
    with :ok <- Jido.Persistence.File.compare_and_swap(key, expected, bytes, opts) do
      case :erlang.binary_to_term(bytes, [:safe]) do
        %{server_turn: %{status: :completed}} -> CompletionProbe.saved()
        _ -> :ok
      end
    end
  end
end
