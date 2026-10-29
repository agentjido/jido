defmodule Jido.Agent.APITest do
  use ExUnit.Case, async: true
  alias Jido.Agent
  alias Jido.Agent.Directive
  alias Jido.Persistence
  alias Jido.Signal

  defmodule Audit do
    use Jido.Plugin, id: "test.api.audit"
    def state_spec(_), do: {:turns, Zoi.integer() |> Zoi.default(0)}
    def reduce(reduction, _), do: {:ok, reduction.plugin_state + 1}
  end

  defmodule Counter do
    use Jido.Agent, name: "api_counter", plugins: [Jido.Agent.APITest.Audit]

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      signal_source "/counter"

      route "increment", as: :increment do
        action %{amount: amount}, context: context do
          count = context.agent_state.count + amount
          {:ok, %{context.agent_state | count: count}, [emit("updated", %{count: count})]}
        end
      end
    end
  end

  test "there is one validation call and one public state schema accessor" do
    definition = Counter.definition()
    assert %Agent{id: nil, state: nil} = definition
    assert {:ok, ^definition} = Agent.validate(definition)
    instance = Counter.instantiate!(id: "schema")
    assert {:ok, ^instance} = Agent.validate(instance)
    assert {:error, _} = Agent.validate(%{instance | state: %{count: "wrong", turns: 0}})
    assert Counter.schema() === Agent.schema(definition)

    assert {:ok, %{count: 2, turns: 3}} =
             Zoi.parse(Agent.schema(instance), %{count: 2, turns: 3})

    refute function_exported?(Agent, :validate_definition, 1)
    refute function_exported?(Agent, :validate_instance, 1)
    refute function_exported?(Agent, :schema, 0)
    refute function_exported?(Counter, :domain_schema, 0)
    refute function_exported?(Counter, :complete_schema, 0)
    refute function_exported?(Agent, :handle_signal, 2)
    refute function_exported?(Agent, :emit, 2)
    refute function_exported?(Agent, :checkpoint, 1)
    refute function_exported?(Agent, :restore, 2)
    refute function_exported?(Agent, :new, 1)
    refute function_exported?(Agent, :new!, 1)
    refute function_exported?(Counter, :new, 0)
    refute function_exported?(Counter, :new, 1)
    refute function_exported?(Counter, :new!, 0)
    refute function_exported?(Counter, :new!, 1)
  end

  test "plugins prepare and reduce a complete command without persistence" do
    instance = Counter.instantiate!(id: "command")
    {:ok, input} = Counter.increment_signal(%{amount: 2})
    assert {:ok, after_agent, [%Directive.Emit{signal: output}]} = Agent.cmd(instance, input)
    assert after_agent.state === %{count: 2, turns: 1}
    assert output.type == "updated" and output.source == "/counter"
    assert instance.state === %{count: 0, turns: 0}
    assert after_agent.plugins === instance.plugins
  end

  test "build_signal uses the Agent source and correlates the source Signal" do
    source = Signal.new!("request", %{}, source: "/caller")
    {:ok, source, trace} = Signal.Trace.ensure(source)

    assert {:ok, output} =
             Agent.build_signal(
               %{agent_signal_source: "/counter", signal: source},
               "progress",
               %{step: 1}
             )

    assert output.type == "progress"
    assert output.data == %{step: 1}
    assert output.source == "/counter"
    assert Signal.get_context(output, "jidocausationid") == source.id
    assert Signal.Trace.get(output) == trace

    assert {:error, %Jido.Error.ValidationError{}} =
             Agent.build_signal(%{}, "progress", %{step: 1})
  end

  test "persistence saves and loads the Agent value explicitly, including Plugin state" do
    source = {Persistence.ETS, [table: __MODULE__]}
    instance = Counter.instantiate!(id: "persist-#{System.unique_integer([:positive])}")
    {:ok, input} = Counter.increment_signal(%{amount: 3})
    {:ok, candidate, [_]} = Agent.cmd(instance, input)

    assert {:error, :not_found} =
             Persistence.load_agent(source, Counter, instance.id, namespace: "api-test")

    assert :ok = Persistence.create_agent(source, instance, namespace: "api-test")

    assert {:ok, ^instance} =
             Persistence.load_agent(source, Counter, instance.id, namespace: "api-test")

    assert :ok =
             Persistence.save_agent(source, candidate,
               namespace: "api-test",
               expected_revision: 0,
               revision: 1
             )

    assert {:ok, ^candidate, 1} =
             Persistence.load_agent_with_revision(source, Counter, instance.id,
               namespace: "api-test"
             )

    assert :ok = Persistence.delete_agent(source, Counter, instance.id, namespace: "api-test")

    assert {:error, :deleted} =
             Persistence.load_agent(source, Counter, instance.id, namespace: "api-test")
  end
end
