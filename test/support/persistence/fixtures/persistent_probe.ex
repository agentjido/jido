defmodule JidoTest.Persistence.PersistentProbe do
  @moduledoc false

  use Jido.Agent, name: "persistence_contract_probe"

  state do
    schema Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/test/persistence/probe"

    route "test.persistence.probe.set", as: :set do
      action %{value: value},
        schema: Zoi.object(%{value: Zoi.integer()}),
        output_schema: Zoi.map(),
        context: _context do
        {:ok, %{value: value}}
      end

      state(from: output())
    end

    route "test.persistence.probe.keep", as: :keep do
      action _input, output_schema: Zoi.map(), context: context do
        {:ok, context.agent_state}
      end

      state(from: output())
    end

    route "test.persistence.probe.set_and_emit", as: :set_and_emit do
      action %{value: value},
        schema: Zoi.object(%{value: Zoi.integer()}),
        output_schema: Zoi.map(),
        context: context do
        signal =
          Jido.Signal.new!(
            "test.persistence.probe.committed",
            %{value: value},
            source: "/test/persistence/probe"
          )

        directives =
          if observer = context[:observer] do
            [Jido.AgentServer.Directive.signal_send(signal, observer)]
          else
            []
          end

        {:ok, %{value: value}, directives}
      end

      state(from: output())
    end
  end
end
