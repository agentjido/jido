defmodule Jido.AgentServer.Snapshot do
  @moduledoc "The complete committed Agent view for one resident activation."

  alias Jido.Agent
  alias Jido.Agent.Ref

  @enforce_keys [
    :agent,
    :agent_ref,
    :agent_activation_id,
    :agent_revision,
    :persistence_revision,
    :durability
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          agent: Agent.t(),
          agent_ref: Ref.t(),
          agent_activation_id: String.t(),
          agent_revision: non_neg_integer(),
          persistence_revision: non_neg_integer() | nil,
          durability: :memory | :durable
        }

  @doc false
  def new(data) do
    %__MODULE__{
      agent: data.agent,
      agent_ref: data.agent_ref,
      agent_activation_id: data.agent_activation_id,
      agent_revision: data.agent_revision,
      persistence_revision: data.persistence_revision,
      durability: if(data.persistence in [nil, false], do: :memory, else: :durable)
    }
  end
end
