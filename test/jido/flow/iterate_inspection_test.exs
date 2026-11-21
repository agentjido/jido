defmodule Jido.Flow.IterateInspectionTest do
  use ExUnit.Case, async: true

  alias Jido.Joi

  defmodule Count do
    use Jido.Action, name: "iterate_inspection_count", schema: Joi.object(%{n: Joi.integer()})

    def run(%{n: n}, _context), do: {:ok, %{n: n + 1}}
  end

  @state_schema Joi.object(%{n: Joi.integer()})

  defmodule CountFlow do
    use Jido.Flow, name: "iterate_inspection_flow"

    flow do
      iterate "loop" do
        state Joi.object(%{n: Joi.integer()}), initial: %{n: 0}
        action Count
        params %{n: state(:n)}
        update %{n: body_result(:n)}
        while state(:n) < 2
        max_iterations 5
      end

      output result("loop")
    end
  end

  test "to_map keeps an Iterate state schema as its Joi value" do
    map = Jido.Flow.to_map(CountFlow.flow())

    assert [%{name: "loop", state: %{schema: @state_schema, initial: %{n: 0}}}] = map.components
  end

  test "explain returns for an Iterate Flow" do
    assert {:ok, %{components: [%{state: %{schema: @state_schema}}]}} =
             Jido.Flow.explain(CountFlow.flow())
  end

  test "to_map and explain return for the ReAct Flow" do
    flow = Jido.AI.Reasoning.ReAct.flow()

    assert %{name: name, components: [_ | _]} = Jido.Flow.to_map(flow)
    assert {:ok, %{name: ^name, components: [_ | _]}} = Jido.Flow.explain(flow)
  end
end
