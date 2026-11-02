defmodule Jido.Flow.DSL.ValueParserTest do
  use ExUnit.Case, async: true

  alias Jido.Expr
  alias Jido.Flow.DSL.{Step, ValueParser}
  alias Jido.Flow.Ref

  test "parses every Flow reference form" do
    cases = [
      {"input()", Ref.input()},
      {"input(:value)", Ref.input(:value)},
      {"context([:tenant, \"id\"])", Ref.context([:tenant, "id"])},
      {"item()", Ref.item()},
      {"item(:id)", Ref.item(:id)},
      {"item_index()", Ref.item_index()},
      {"accumulator()", Ref.accumulator()},
      {"accumulator(:total)", Ref.accumulator(:total)},
      {"state()", Ref.state()},
      {"state(:count)", Ref.state(:count)},
      {"iteration_index()", Ref.iteration_index()},
      {"body_result()", Ref.body_result()},
      {"body_result(:value)", Ref.body_result(:value)},
      {"result(:load)", Ref.result("load")},
      {"result(\"load\", [:value, 0])", Ref.result("load", [:value, 0])},
      {"select(result(:load), [:value, 0])", Ref.result("load", [:value, 0])}
    ]

    for {source, expected} <- cases do
      assert {:ok, ^expected} = source |> ast() |> ValueParser.parse()
    end
  end

  test "parses literal containers and expressions" do
    assert {:ok, %{name: "Ada", values: [1, -2, true]}} =
             "%{name: \"Ada\", values: [1, -2, true]}"
             |> ast()
             |> ValueParser.parse()

    assert {:ok, -2} = "value(-2)" |> ast() |> ValueParser.parse()

    assert {:ok, %Expr{operator: :+, operands: [%Ref{source: :input}, 1]}} =
             "input(:value) + 1" |> ast() |> ValueParser.parse()
  end

  test "rejects duplicate keys, invalid containers, and unsupported calls" do
    assert {:error, error} = "%{a: 1, a: 2}" |> ast() |> ValueParser.parse()
    assert error.message == "duplicate Flow map key"

    for quoted <- [
          quote(do: %{[] => 1}),
          quote(do: [1 | 2]),
          quote(do: unknown_call()),
          quote(do: result("")),
          quote(do: select(1, [:value]))
        ] do
      assert {:error, %Jido.Flow.Error.InvalidDefinitionError{}} = ValueParser.parse(quoted)
    end
  end

  test "parses selected entity fields and attaches source locations" do
    entity = %Step{params: ast("input(:value)"), __source__: %{line: 12, column: 4}}

    assert {:ok, %{params: %Ref{source: :input, path: [:value]}}} =
             ValueParser.parse_fields(entity, params: :value)

    invalid = %Step{params: {:unknown_call, [], []}, __source__: %{line: 14, column: 2}}
    assert {:error, error} = ValueParser.parse_fields(invalid, params: :value)
    assert error.details.line == 14
    assert error.details.column == 2
  end

  defp ast(source), do: Code.string_to_quoted!(source, line: 7, column: 3)
end
