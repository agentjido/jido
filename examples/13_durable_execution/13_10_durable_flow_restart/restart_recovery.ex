defmodule Jido.Examples.Durability.RestartRecovery do
  @moduledoc "Restores one waiting Flow after its Jido instance restarts."
  use Jido.Flow, name: "example_durable_restart_recovery"

  flow do
    await "approval",
      event: "examples.durable.order.approved",
      match: %{order_id: input(:order_id)}

    output result("approval")
  end
end
