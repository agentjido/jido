defmodule Jido.AgentServer.TurnResult do
  @moduledoc """
  The process-neutral result of one accepted Agent Turn.

  A terminal status is data. `{:error, reason}` is reserved for work that was
  not accepted or for a failed transport operation.
  """

  alias Jido.Agent.Address
  alias Jido.Exec.Wait
  alias Jido.Signal

  @type status :: :committed | :waiting | :failed | :cancelled | :timed_out | :uncertain
  @type durability :: :memory | :durable | :unknown

  @enforce_keys [
    :turn_id,
    :agent_address,
    :agent_activation_id,
    :status,
    :durability,
    :agent_revision,
    :persistence_revision
  ]
  defstruct [
    :turn_id,
    :agent_address,
    :agent_activation_id,
    :status,
    :durability,
    :agent_revision,
    :persistence_revision,
    :reply,
    :error,
    waits: [],
    effects: :none
  ]

  @type t :: %__MODULE__{
          turn_id: String.t(),
          agent_address: Address.t(),
          agent_activation_id: String.t(),
          status: status(),
          durability: durability(),
          agent_revision: non_neg_integer(),
          persistence_revision: non_neg_integer() | nil,
          reply: Signal.t() | nil,
          waits: [Wait.t()],
          effects: :none | :pending,
          error: term() | nil
        }
end
