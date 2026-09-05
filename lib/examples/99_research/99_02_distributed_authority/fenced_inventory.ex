defmodule Jido.Examples.FencedInventory.Authority do
  @moduledoc """
  Controlled external authority, byte store, and fenced sink for one inventory ID.
  All token checks and storage changes serialize in this process. This fixture
  has no consensus, lease, disk durability, or automatic failover policy.
  """
  use GenServer
  def start_link(_), do: GenServer.start_link(__MODULE__, %{token: 0, records: %{}, effects: []})
  def start_probe, do: Supervisor.start_child(Jido.Supervisor, {Elixir.Agent, fn -> 0 end})
  def claim(authority), do: request(authority, :claim)
  def check(authority, token), do: request(authority, {:check, token})
  def effect(authority, token, value), do: request(authority, {:effect, token, value})
  def effects(authority), do: request(authority, :effects)

  def request(authority, message) do
    GenServer.call(authority, message, 1_000)
  catch
    :exit, _ -> {:error, :authority_unavailable}
  end

  @impl true
  def init(state), do: {:ok, state}
  @impl true
  def handle_call(:claim, _, state),
    do: {:reply, state.token + 1, %{state | token: state.token + 1}}

  def handle_call(:effects, _, state), do: {:reply, state.effects, state}
  def handle_call({:check, token}, _, %{token: token} = state), do: {:reply, :ok, state}

  def handle_call({:effect, token, value}, _, %{token: token} = state) do
    {:reply, :ok, %{state | effects: state.effects ++ [{token, value}]}}
  end

  def handle_call({:store, token, operation}, _, %{token: token} = state) do
    {reply, records} = store(operation, state.records)
    {:reply, reply, %{state | records: records}}
  end

  def handle_call(_, _, state), do: {:reply, {:error, :stale_owner}, state}

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
  @moduledoc "A byte adapter that checks the current ownership token for every operation."
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
  @moduledoc "Application-owned local activation configuration. Runtime handles stay outside checkpoints."
  use GenServer
  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def configure(id, config), do: GenServer.call(__MODULE__, {:configure, id, config})
  def config(id), do: GenServer.call(__MODULE__, {:config, id})
  @impl true
  def init(state), do: {:ok, state}
  @impl true
  def handle_call({:configure, id, config}, _, state),
    do: {:reply, :ok, Map.put(state, id, config)}

  def handle_call({:config, id}, _, state), do: {:reply, Map.fetch(state, id), state}
end

defmodule Jido.Examples.FencedInventory.Gate do
  @moduledoc "Checks external ownership through the current public live admission callback."
  use Jido.Plugin
  alias Jido.Examples.FencedInventory.{Authority, Client}

  def admit(nil, command, _) do
    with {:ok, config} <- Client.config(command.agent.id),
         :ok <- Authority.check(config.authority, config.token) do
      {:ok, %{command | context: Map.merge(command.context, config)}}
    else
      error ->
        {:error,
         Jido.Error.validation_error("activation has no write authority",
           details: %{cause: error}
         )}
    end
  end
end

defmodule Jido.Examples.FencedInventory do
  @moduledoc """
  Inventory with externally fenced admission, persistence, and sink writes.
  This uses the current live admit callback. If core removes that callback,
  the example must be rerun against the replacement admission boundary.
  """
  use Jido.Agent, name: "research_fenced_inventory"

  agent do
    plugin Jido.Examples.FencedInventory.Gate
    schema Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/examples/fenced-inventory"

    route "inventory.record" do
      action %{value: value},
        name: "research_inventory_record",
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        Elixir.Agent.update(context.probe, &(&1 + 1))

        with :ok <-
               Jido.Examples.FencedInventory.Authority.effect(
                 context.authority,
                 context.token,
                 value
               ) do
          {:ok, %{context.agent_state | value: value}}
        end
      end

      define :record, args: [:value]
    end
  end

  def probe_count(probe), do: Elixir.Agent.get(probe, & &1)
end
