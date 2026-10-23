defmodule Jido.Examples.OTPSupervision.Counter do
  @moduledoc "A counter placed directly in an application supervision tree."
  use Jido.Agent, name: "otp_supervision_counter"

  state do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})

    # This standard Plugin makes Agent-owned runtime cleanup visible in the
    # process tree. This example does not schedule work.
  end

  plugins do
    plugin Jido.Plugin.Scheduler
  end

  routes do
    signal_source "/examples/basic/otp_supervision"

    route "examples.basic.otp_supervision.increment", as: :increment, defaults: %{amount: 1} do
      action %{amount: amount},
        schema: Zoi.object(%{amount: Zoi.integer()}),
        context: context,
        output_schema: Zoi.map() do
        {:ok, %{context.agent_state | count: context.agent_state.count + amount}}
      end

      state(from: output())
    end
  end
end
