defmodule Jido.Examples.OwnershipTransfer do
  @moduledoc "Adopts and transfers one local resident Agent with a public fence."

  alias Jido.Agent.Address
  alias Jido.AgentOwnership

  def adopt(instance, %Address{} = child, %Address{} = owner, request_id) do
    Jido.transfer_agent_ownership(instance, child, owner,
      expected: nil,
      request_id: request_id
    )
  end

  def transfer(
        instance,
        %Address{} = child,
        %Address{} = owner,
        %AgentOwnership{} = expected,
        request_id
      ) do
    Jido.transfer_agent_ownership(instance, child, owner,
      expected: expected,
      request_id: request_id
    )
  end
end
