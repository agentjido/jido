defmodule Jido.Examples.FencedInventory.Authority do
  @moduledoc "A controlled external authority, byte store, and fenced sink."
  use GenServer

  def start_link(_opts),
    do: GenServer.start_link(__MODULE__, %{token: 0, records: %{}, effects: []})

  def claim(authority), do: request(authority, :claim)
  def check(authority, token), do: request(authority, {:check, token})
  def effect(authority, token, value), do: request(authority, {:effect, token, value})
  def effects(authority), do: request(authority, :effects)

  def request(authority, message) do
    GenServer.call(authority, message, 1_000)
  catch
    :exit, _reason -> {:error, :authority_unavailable}
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:claim, _from, state),
    do: {:reply, state.token + 1, %{state | token: state.token + 1}}

  def handle_call(:effects, _from, state), do: {:reply, state.effects, state}
  def handle_call({:check, token}, _from, %{token: token} = state), do: {:reply, :ok, state}

  def handle_call({:effect, token, value}, _from, %{token: token} = state) do
    {:reply, :ok, %{state | effects: state.effects ++ [{token, value}]}}
  end

  def handle_call({:store, token, operation}, _from, %{token: token} = state) do
    {reply, records} = store(operation, state.records)
    {:reply, reply, %{state | records: records}}
  end

  def handle_call(_request, _from, state), do: {:reply, {:error, :stale_owner}, state}

  defp store({:get, key}, records) do
    result =
      case Map.fetch(records, key) do
        {:ok, value} -> {:ok, value}
        :error -> {:error, :not_found}
      end

    {result, records}
  end

  defp store({:put, key, value}, records), do: {:ok, Map.put(records, key, value)}
  defp store({:delete, key}, records), do: {:ok, Map.delete(records, key)}

  defp store({:cas, key, expected, value}, records) do
    if Map.get(records, key, :not_found) == expected,
      do: {:ok, Map.put(records, key, value)},
      else: {{:error, :conflict}, records}
  end
end

defmodule Jido.Examples.FencedInventory.Store do
  @moduledoc "A byte adapter that checks the ownership token for every operation."
  @behaviour Jido.Persistence.Adapter

  def get(key, opts), do: request(opts, {:get, key})
  def put(key, value, opts), do: request(opts, {:put, key, value})
  def delete(key, opts), do: request(opts, {:delete, key})

  def compare_and_swap(key, expected, value, opts),
    do: request(opts, {:cas, key, expected, value})

  defp request(opts, operation) do
    Jido.Examples.FencedInventory.Authority.request(
      Keyword.fetch!(opts, :authority),
      {:store, Keyword.fetch!(opts, :token), operation}
    )
  end
end

defmodule Jido.Examples.FencedInventory.Client do
  @moduledoc "Keeps activation configuration outside Agent checkpoints."
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def configure(id, config), do: GenServer.call(__MODULE__, {:configure, id, config})
  def config(id), do: GenServer.call(__MODULE__, {:config, id})

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:configure, id, config}, _from, state),
    do: {:reply, :ok, Map.put(state, id, config)}

  def handle_call({:config, id}, _from, state), do: {:reply, Map.fetch(state, id), state}
end
