defmodule Jido.Test.Examples.Durable.CompletionProbe do
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

defmodule Jido.Test.Examples.Durable.CompletionStorage do
  @moduledoc false
  @behaviour Jido.Persistence.Store
  alias Jido.Test.Examples.Durable.CompletionProbe

  @impl Jido.Persistence.Store
  def validate_options(opts), do: Jido.Persistence.File.validate_options(opts)

  @impl Jido.Persistence.Store
  def get(key, opts), do: Jido.Persistence.File.get(key, opts)

  @impl Jido.Persistence.Store
  def compare_and_swap(key, expected, bytes, opts) do
    with :ok <- Jido.Persistence.File.compare_and_swap(key, expected, bytes, opts) do
      case Jido.Persistence.Codec.Term.decode(bytes, trusted: true) do
        {:ok, %{server_turn: %{status: :completed}}} -> CompletionProbe.saved()
        _ -> :ok
      end
    end
  end

  @impl Jido.Persistence.Store
  def delete(key, opts), do: Jido.Persistence.File.delete(key, opts)
end
