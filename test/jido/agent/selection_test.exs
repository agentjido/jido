defmodule Jido.Agent.SelectionTest do
  use JidoTest.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.{Command, Runner}
  alias Jido.AgentServer, as: Server
  alias Jido.Tracing.Trace

  defmodule Record do
    use Jido.Action,
      name: "selection_record",
      output_schema: Zoi.any()

    @impl true
    def run(input, context) do
      if observer = Map.get(context, :observer) do
        send(observer, {:executed, input, context.signal})
      end

      {:ok, %{input: input, calls: context.agent_state.calls + 1}}
    end
  end

  defmodule RecordFlow do
    use Jido.Flow,
      name: "selection_record_flow",
      output_schema: Zoi.any()

    flow do
      step "record", action: Record, params: input()
      output result("record")
    end
  end

  defmodule ValidatedRecord do
    use Jido.Action,
      name: "selection_validated_record",
      schema: Zoi.object(%{value: Zoi.integer()}),
      output_schema: Zoi.any()

    @impl true
    def run(input, context), do: Record.run(input, context)
  end

  defmodule RoutedAgent do
    use Jido.Agent, name: "selection_routed"

    state do
      schema Zoi.object(%{
               input: Zoi.map() |> Zoi.default(%{}),
               calls: Zoi.integer() |> Zoi.default(0)
             })
    end

    routes do
      route "selection.action", Record, defaults: %{value: 7, settings: %{first: 1, second: 2}} do
        state(from: output())
      end

      route "selection.flow", RecordFlow,
        defaults: %{value: 7, settings: %{first: 1, second: 2}} do
        state(from: output())
      end
    end
  end

  test "declared routes in Map and DSL definitions prepare the same Turn", %{
    jido: jido
  } do
    defaults = %{value: 7, settings: %{first: 1, second: 2}}

    cases = [
      {%{}, defaults},
      {nil, defaults},
      {[], defaults},
      {[value: 3], %{defaults | value: 3}},
      {[value: 1, value: 3], %{defaults | value: 3}},
      {%{value: nil}, %{defaults | value: nil}},
      {%{value: false}, %{defaults | value: false}},
      {%{value: 0}, %{defaults | value: 0}},
      {%{value: 3, settings: %{second: 9}}, %{value: 3, settings: %{second: 9}}},
      {%{"value" => 3}, Map.put(defaults, "value", 3)}
    ]

    for definition <- definitions(),
        {type, target} <- [{"selection.action", Record}, {"selection.flow", RecordFlow}],
        {data, input} <- cases do
      agent = Agent.instantiate!(definition, id: Jido.Signal.ID.generate!())
      source = signal(type, data)

      assert {:ok, prepared} = Runner.prepare(agent, source, [])
      turn = prepared.turn
      assert turn.executable == target
      assert turn.input == input
      assert turn.source_signal == source

      assert {:ok, direct, []} = Agent.cmd(agent, source, context: %{observer: self()})
      assert_receive {:executed, ^input, ^source}
      assert direct.state == %{input: input, calls: 1}

      assert {:ok, server} = JidoTest.AgentServerAssertions.start_agent(jido, agent)
      assert {:ok, live, _} = Server.call(server, source, context: %{observer: self()})
      assert_receive {:executed, ^input, execution_signal}
      assert execution_signal.data == source.data
      assert live.state == direct.state
      assert :ok = Jido.stop_agent(jido, server)
    end
  end

  test "routes without defaults accept empty input in direct and live calls", %{jido: jido} do
    for target <- [Record, RecordFlow], data <- [nil, []] do
      definition =
        Agent.define!(%{
          name: "selection_no_defaults",
          schema: RoutedAgent.definition().schema,
          routes: [
            %{
              path: "selection.empty",
              handler: %{
                kind: if(target == RecordFlow, do: :flow, else: :action),
                target: target
              },
              state: %{source: :output, path: []}
            }
          ]
        })

      agent = Agent.instantiate!(definition, id: Jido.Signal.ID.generate!())
      source = signal("selection.empty", data)
      assert {:ok, server} = JidoTest.AgentServerAssertions.start_agent(jido, agent)
      assert {:ok, direct, []} = Agent.cmd(agent, source)
      assert {:ok, live, _} = Server.call(server, source)
      assert direct.state == %{input: %{}, calls: 1}
      assert live.state == direct.state
    end
  end

  test "invalid route data returns its Signal context before executable work", %{jido: jido} do
    for definition <- definitions() do
      agent = Agent.instantiate!(definition, id: Jido.Signal.ID.generate!())
      assert {:ok, server} = JidoTest.AgentServerAssertions.start_agent(jido, agent)

      for data <- ["hello", 3, [1, 2], [{"value", 3}], [{:value, 3} | :invalid]] do
        source = signal("selection.action", data)

        for result <- [
              Runner.prepare(agent, source, []),
              Agent.cmd(agent, source, context: %{observer: self()}),
              Server.call(server, source, context: %{observer: self()})
            ] do
          assert {:error,
                  %Jido.Error.ValidationError{
                    subject: :data,
                    details: %{signal_id: id, data: ^data}
                  }} = result

          assert id == source.id
        end

        assert Server.agent(server).state == agent.state
        refute_received {:executed, _, _}
      end
    end
  end

  test "invalid supplied values fail executable validation instead of using defaults", %{
    jido: jido
  } do
    agent =
      Agent.define!(%{
        name: "selection_invalid_value",
        schema: RoutedAgent.definition().schema,
        routes: [
          %{
            path: "selection.validated",
            handler: %{kind: :action, target: ValidatedRecord},
            defaults: %{value: 7},
            state: %{source: :output, path: []}
          }
        ]
      })
      |> Agent.instantiate!(id: Jido.Signal.ID.generate!())

    source = signal("selection.validated", value: "invalid")
    assert {:ok, server} = JidoTest.AgentServerAssertions.start_agent(jido, agent)
    assert {:error, _error} = Agent.cmd(agent, source, context: %{observer: self()})
    assert {:error, _error} = Server.call(server, source, context: %{observer: self()})
    assert Server.agent(server).state == agent.state
    refute_received {:executed, _, _}
  end

  test "selection keeps the original source separate from execution Signal metadata" do
    for module <- [RoutedAgent] do
      source = signal("selection.action", %{})
      assert {:ok, command} = Command.new(module.instantiate!(id: "source"), source)
      assert {:ok, execution_signal} = Trace.put(source, Trace.new_root())
      refute execution_signal.extensions == source.extensions
      command = %{command | signal: execution_signal}

      assert {:ok, prepared} = Runner.prepare_for_server(command, source, [], [])
      assert prepared.turn.source_signal == source
      assert prepared.signal == execution_signal
      assert prepared.context.signal == execution_signal
    end
  end

  defp definitions do
    [
      RoutedAgent.definition(),
      Agent.define!(%{
        name: "selection_data",
        schema: RoutedAgent.definition().schema,
        routes: RoutedAgent.definition().routes
      })
    ]
  end
end
