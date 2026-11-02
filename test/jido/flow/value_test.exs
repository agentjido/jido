defmodule Jido.Flow.ValueTest do
  use ExUnit.Case, async: true

  alias Jido.Flow.{Ref, Value}

  test "normalizes nested references and returns result dependencies in tree order" do
    expression = %{
      first: Ref.result(:load, :value),
      nested: [Jido.Expr.new!(:<, [Ref.result(:limit), 10]), Ref.result("load", :other)]
    }

    assert {:ok, normalized} = Value.prepare(expression)
    assert normalized.first.step == "load"
    assert Value.result_refs(normalized) == ["load", "limit", "load"]
    assert Value.to_map(normalized) == normalized
  end

  test "enforces reference scopes before a Flow is compiled" do
    assert {:ok, %Ref{source: :item}} = Value.prepare(Ref.item(), :map)
    assert {:ok, %Ref{source: :accumulator}} = Value.prepare(Ref.accumulator(), :reduce)
    assert {:ok, %Ref{source: :state}} = Value.prepare(Ref.state(), :iterate_params)
    assert {:ok, %Ref{source: :body_result}} = Value.prepare(Ref.body_result(), :iterate_update)

    for {ref, scope} <- [
          {Ref.item(), :flow},
          {Ref.accumulator(), :map},
          {Ref.state(), :reduce},
          {Ref.body_result(), :iterate_params}
        ] do
      assert {:error, error} = Value.prepare(ref, scope)
      assert error.message == "flow expression contains a scoped ref outside its valid scope"
      assert error.details.scope == scope
      assert error.details.ref_type == ref.source
    end
  end

  test "rejects invalid portable data with an exact nested path" do
    assert {:error, error} = Value.validate_data(%{"items" => [1, {:tuple}]})
    assert error.details.path == ["items", 1]
    assert error.details.value_type == :tuple

    assert {:error, error} = Value.validate_data([1 | :tail])
    assert error.details.path == []

    assert {:error, error} = Value.validate_key(-1)
    assert error.details.key == -1

    assert {:error, error} = Value.validate_object([])
    assert error.message == "flow metadata must be a portable map"
  end

  test "enforces depth and integer size limits" do
    nested = Enum.reduce(1..102, 0, fn _index, value -> [value] end)

    assert {:error, depth_error} = Value.prepare(nested)
    assert depth_error.details.reason == :max_depth

    assert {:error, integer_error} = Value.prepare(:erlang.bsl(1, 4096))
    assert integer_error.details.reason == :max_integer_bits
  end

  test "accepts only Boolean-compatible conditions" do
    assert {:ok, true} = Value.condition(true, :flow)
    assert {:ok, %Ref{}} = Value.condition(Ref.input(:enabled), :flow)

    assert {:error, error} = Value.condition(1, :flow)
    assert error.details.path == []
  end

  test "validates complete expressions and reports invalid nested values" do
    expression = Jido.Expr.new!(:<, [Ref.input(:count), 10])

    assert :ok = Value.validate(expression)

    assert {:error, error} = Value.validate(%{"bad" => Date.utc_today()})
    assert error.details.path == ["bad"]
    assert error.details.expression == Date

    assert {:error, error} = Value.validate(%{nil => 1})
    assert error.details.path == []
    assert error.details.key == nil

    assert {:error, error} = Value.validate([1 | :tail])
    assert error.details.reason == :improper_list
  end

  test "reports each unsupported portable data type" do
    values = [
      {fn -> :ok end, :function},
      {self(), :pid},
      {make_ref(), :reference},
      {Date.utc_today(), {:struct, Date}},
      {<<1::1>>, :other}
    ]

    for {value, type} <- values do
      assert {:error, error} = Value.validate_data(value)
      assert error.details.value_type == type
    end

    assert {:error, error} = Value.validate_data(<<255>>)
    assert error.message == "flow data strings must be valid UTF-8"
  end

  test "reports invalid reference paths and shapes" do
    invalid_path = %Ref{source: :input, step: nil, path: [{:bad}]}
    invalid_shape = %Ref{source: :unknown, step: nil, path: []}

    assert {:error, path_error} = Value.prepare(invalid_path)
    assert path_error.message == "flow expression contains an invalid reference path"
    assert path_error.details.segment == {:bad}

    assert {:error, shape_error} = Value.prepare(invalid_shape)
    assert shape_error.message == "flow expression contains an invalid reference"
    assert shape_error.details.ref_type == :unknown
  end
end
