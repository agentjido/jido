defmodule Jido.Examples.Durable.TopologyHandoff do
  @moduledoc "Commits a ticket assignment to a declared responder."

  alias Jido.Agent.Directive
  alias Jido.Joi
  alias Jido.Signal

  use Jido.Agent, name: "example_topology_handoff"

  defmodule Responder do
    use Jido.Agent, name: "example_handoff_responder"

    state do
      schema Joi.object(%{assigned: Joi.integer() |> Joi.default(0)})
    end

    routes do
      route "ticket.assigned" do
        flow do
          step "record", _input <- input(), inline: [context: context] do
            {:ok, %{assigned: context.agent_state.assigned + 1}}
          end

          output result("record")
        end
      end
    end
  end

  routes do
    signal_source "/examples/topology-handoff"

    route "ticket.assign", as: :assign do
      action _input, schema: Joi.object(%{}), context: context do
        signal = Signal.new!("ticket.assigned", %{}, source: "/examples/topology-handoff")
        {:ok, context.agent_state, [Directive.emit(signal, {:durable, {:agent, :responder, 1}})]}
      end
    end
  end

  topology do
    agent :responder, Responder
  end
end
