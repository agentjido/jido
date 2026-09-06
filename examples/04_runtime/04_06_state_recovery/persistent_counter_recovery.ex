defmodule Jido.Examples.PersistentCounterRecovery do
  @moduledoc """
  A Counter that stores handled command IDs in durable Agent state.

  Jido persistence restores the complete Agent and its state version. The
  application-owned command ledger prevents a repeated Signal from changing
  the count twice.
  """

  use Jido.Agent,
    name: "examples_persistent_counter_recovery",
    description: "Restores a counter and rejects duplicate state changes"

  agent do
    schema Zoi.object(%{
             count: Zoi.integer() |> Zoi.default(0),
             handled_signal_ids: Zoi.list(Zoi.string()) |> Zoi.default([]),
             last_command: Zoi.map() |> Zoi.nullable() |> Zoi.default(nil)
           })
  end

  routes do
    route "examples.persistent_counter.increment",
          Jido.Examples.PersistentCounterRecovery.Increment
  end

  alias Jido.AgentServer, as: Server
  alias Jido.Signal

  @doc "Restores a required counter record and starts its Server."
  @spec restore(module(), String.t(), Jido.Persistence.adapter_config(), keyword()) ::
          DynamicSupervisor.on_start_child()
  def restore(jido, id, persistence, opts \\ []) do
    Jido.thaw(
      jido,
      __MODULE__,
      id,
      Keyword.put(opts, :persistence, persistence)
    )
  end

  @doc "Applies one uniquely identified increment command."
  @spec increment(Server.server(), String.t(), integer(), timeout()) :: Server.signal_result()
  def increment(server, command_id, amount \\ 1, timeout \\ 5_000)
      when is_binary(command_id) and is_integer(amount) do
    Server.call(server, increment_signal!(command_id, amount), timeout)
  end

  @doc "Builds one increment Signal with a stable command ID."
  @spec increment_signal!(String.t(), integer()) :: Signal.t()
  def increment_signal!(command_id, amount \\ 1)
      when is_binary(command_id) and is_integer(amount) do
    Signal.new!(
      "examples.persistent_counter.increment",
      %{amount: amount},
      id: command_id,
      source: "/examples/persistent_counter_recovery"
    )
  end
end

defmodule Jido.Examples.PersistentCounterRecovery.Increment do
  @moduledoc false

  use Jido.Action,
    name: "examples_persistent_counter_increment",
    schema: Zoi.object(%{amount: Zoi.integer()})

  @impl Jido.Action
  def run(%{amount: amount}, %{agent_state: state, signal: signal}) do
    if signal.id in state.handled_signal_ids do
      # Success preserves the value but creates one new commit revision.
      {:ok, state}
    else
      {:ok,
       %{
         state
         | count: state.count + amount,
           handled_signal_ids: state.handled_signal_ids ++ [signal.id],
           last_command: %{signal_id: signal.id, amount: amount}
       }}
    end
  end
end
