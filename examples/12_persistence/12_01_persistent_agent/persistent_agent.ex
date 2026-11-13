defmodule Jido.Examples.Persistence.PersistentAgent do
  @moduledoc """
  A Counter that stores handled command IDs in durable Agent state.

  Jido persistence restores the complete Agent and its state version. The
  application-owned command ledger prevents a repeated Signal from changing
  the count twice.
  """

  use Jido.Agent,
    name: "examples_persistent_agent",
    description: "Creates, commits, and restores one persistent Agent"

  state do
    schema Jido.Joi.object(%{
             count: Jido.Joi.integer() |> Jido.Joi.default(0),
             handled_signal_ids: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([]),
             last_command: Jido.Joi.map() |> Jido.Joi.nullable() |> Jido.Joi.default(nil)
           })
  end

  routes do
    route "examples.persistence.persistent_agent.increment" do
      action %{amount: amount},
        schema: Jido.Joi.object(%{amount: Jido.Joi.integer()}),
        context: context do
        state = context.agent_state
        signal_id = context.signal.id

        if signal_id in state.handled_signal_ids do
          # The successful retry keeps the same value but creates a new commit.
          {:ok, state}
        else
          {:ok,
           %{
             state
             | count: state.count + amount,
               handled_signal_ids: state.handled_signal_ids ++ [signal_id],
               last_command: %{signal_id: signal_id, amount: amount}
           }}
        end
      end
    end
  end

  alias Jido.AgentServer, as: Server
  alias Jido.Signal

  @doc "Restores a required counter record and starts its Server."
  @spec restore(module(), String.t(), keyword()) ::
          DynamicSupervisor.on_start_child()
  def restore(jido, id, opts \\ []), do: Jido.thaw(jido, __MODULE__, id, opts)

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
      "examples.persistence.persistent_agent.increment",
      %{amount: amount},
      id: command_id,
      source: "/examples/persistence/persistent_agent"
    )
  end
end
