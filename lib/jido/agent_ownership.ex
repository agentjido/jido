defmodule Jido.AgentOwnership do
  @moduledoc """
  A fenced local ownership relation for one resident Agent activation.

  The value identifies the child Agent, its current owner Agent, the fence for
  that exact relation, and the request that created it. It contains no process
  identifier and is not a credential.

  Ownership is activation-scoped runtime data. It survives replacement of an
  AgentServer worker inside the same activation. It does not survive child
  activation loss, passivation, or Jido instance shutdown, and it is not saved
  in the Agent persistence record.
  """

  alias Jido.Agent.Address

  @enforce_keys [:agent_address, :owner_address, :fence, :request_id]
  defstruct [:agent_address, :owner_address, :fence, :request_id]

  @type t :: %__MODULE__{
          agent_address: Address.t(),
          owner_address: Address.t(),
          fence: String.t(),
          request_id: String.t()
        }
end
