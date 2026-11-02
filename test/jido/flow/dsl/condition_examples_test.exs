defmodule JidoActionTest.Flow.DSL.ConditionExamplesTest do
  use ExUnit.Case, async: true

  alias Jido.Flow.DSL.ValueParser

  defmodule BooleanRoute do
    use Jido.Flow,
      name: "required_boolean_route",
      schema: Zoi.object(%{enabled: Zoi.boolean()})

    alias JidoActionTest.Fixtures.Actions.EchoParamsAction

    flow do
      choice "route" do
        option "disabled",
          condition: input(:enabled) == false,
          action: JidoActionTest.Fixtures.Actions.EchoParamsAction,
          params: %{enabled: false}

        otherwise action: EchoParamsAction, params: %{enabled: true}
      end

      output(result("route"))
    end
  end

  test "Boolean comparison routes valid values and schema rejects missing or invalid input" do
    for enabled <- [true, false] do
      assert Jido.Exec.run(BooleanRoute, %{enabled: enabled}) == {:ok, %{enabled: enabled}}
    end

    for input <- [%{}, %{enabled: nil}, %{enabled: "false"}, %{enabled: 0}] do
      assert {:error, error} = Jido.Exec.run(BooleanRoute, input)
      assert Jido.Flow.Error.to_map(error).type == :validation_error
    end
  end

  test "not accepts both conditions and Boolean references" do
    assert {:ok, _} = ValueParser.parse_condition(quote(do: not (input(:enabled) == true)))
    assert {:ok, _} = ValueParser.parse_condition(quote(do: state(:done) == false))
    assert {:ok, _} = ValueParser.parse_condition(quote(do: not input(:enabled)))
    assert {:ok, _} = ValueParser.parse_condition(quote(do: not state(:done)))
  end
end
