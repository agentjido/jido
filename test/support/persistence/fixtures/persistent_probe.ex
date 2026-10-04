defmodule JidoTest.Persistence.PersistentProbe do
  @moduledoc false

  use Jido.Agent, name: "persistence_contract_probe"

  agent do
    schema Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/test/persistence/probe"

    route "test.persistence.probe.set", as: :set do
      action %{value: value},
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: _context do
        {:ok, %{value: value}}
      end
    end

    route "test.persistence.probe.keep", as: :keep do
      action _input, context: context do
        {:ok, context.agent_state}
      end
    end

    route "test.persistence.probe.set_and_emit", as: :set_and_emit do
      action %{value: value},
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        signal =
          Jido.Signal.new!(
            "test.persistence.probe.committed",
            %{value: value},
            source: "/test/persistence/probe"
          )

        directives =
          if observer = context[:observer] do
            [Jido.Agent.Directive.emit_to_pid(signal, observer)]
          else
            []
          end

        {:ok, %{value: value}, directives}
      end
    end
  end
end
