defmodule Jido.Flow.ValueTest do
  use ExUnit.Case, async: true

  alias Jido.Expr
  alias Jido.Flow.{Ref, Value}

  test "portable data validation accepts objects and reports exact nested paths" do
    assert :ok = Value.validate_object(%{"owner" => "team", 1 => [:ready]})
    assert :ok = Value.validate_data([nil, true, 1, 1.5, :ready, "text"])
    assert {:error, _error} = Value.validate_object([])

    for {value, message, path} <- [
          {%{outer: [0, %{inner: self()}]}, "flow data contains an unsupported value", [:outer, 1, :inner]},
          {%{outer: [0, %{nil: :value}]}, "flow data contains an unsupported map key", [:outer, 1]},
          {%{outer: [0, <<255>>]}, "flow data strings must be valid UTF-8", [:outer, 1]},
          {%{outer: [[self() | :tail]]}, "flow data must contain proper lists", [:outer, 0]}
        ] do
      assert {:error, error} = Value.validate_data(value)
      assert error.message == message
      assert error.details.path == path
    end
  end

  test "portable map keys use the same rules in data and Flow values" do
    for key <- ["name", 0, :name] do
      assert :ok = Value.validate_key(key)
      assert :ok = Value.validate_data(%{key => :value})
      assert :ok = Value.validate(%{key => :value})
    end

    for key <- [-1, nil, 1.5, {:tuple}, <<255>>] do
      assert {:error, key_error} = Value.validate_key(key)
      assert {:error, data_error} = Value.validate_data(%{key => :value})
      assert {:error, value_error} = Value.validate(%{key => :value})

      assert data_error.message == key_error.message
      assert value_error.message == key_error.message
    end
  end

  test "Flow validation uses one traversal for expression paths and result references" do
    value = %{
      outer: [
        Expr.new!(:+, [Ref.result(:first, :count), 1]),
        Ref.result("second")
      ]
    }

    assert {:ok, normalized} = Value.prepare(value)
    assert Value.result_refs(normalized) == ["first", "second"]

    invalid = %{outer: [Expr.new!(:+, [Ref.item(), 1])]}
    assert {:error, error} = Value.validate(invalid, :flow)
    assert error.details.path == [:outer, 0, :operands, 0]
  end

  test "plain Flow data keeps its independent in-memory size contract" do
    value = %{nested: Enum.reduce(1..129, 1, fn _, child -> [child] end)}

    assert :ok = Value.validate(value)
    assert {:ok, ^value} = Value.normalize(value)
  end

  test "the complete Flow value tree has bounded depth and node counts" do
    too_deep = Enum.reduce(1..257, 1, fn _, child -> [child] end)

    for operation <- [&Value.normalize/1, &Value.validate/1] do
      assert {:error, depth_error} = operation.(too_deep)
      assert depth_error.details.reason == :max_depth

      assert {:error, node_error} = operation.(List.duplicate(nil, 100_000))
      assert node_error.details.reason == :max_nodes
    end
  end
end
