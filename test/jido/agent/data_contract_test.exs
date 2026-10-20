defmodule Jido.Agent.DataContractTest do
  use Covenant.Case, component: "jido.agent", async: true

  alias Jido.Agent.{Data, Error}

  defp assert_error(result, code, details \\ %{}) do
    assert {:error, %Error{code: ^code, message: message, details: ^details}} = result
    assert message != ""
  end

  @tag obligation: ["jido.agent.I3", "jido.agent.I7", "jido.agent.I22"]
  test "scalar authoring validators keep their exact boundaries" do
    assert :ok = Data.nonempty("a")

    for value <- [nil, true, false] do
      assert_error(Data.name(value), :invalid_name)
    end

    assert_error(Data.nonempty(""), :invalid_string)
    assert_error(Data.positive(0), :invalid_positive)
  end

  @tag obligation: ["jido.agent.I3", "jido.agent.I22"]
  test "collection errors retain the failed field, declaration, and index" do
    assert_error(Data.fields(%{bad: 1}, []), :unknown_fields, %{keys: [:bad]})
    assert_error(Data.unique([:a, :a], & &1), :duplicate, %{values: [:a, :a]})

    result =
      Data.list([:ok, :ok, :bad], fn
        :bad -> Error.fail(:bad_item, [], "Bad item")
        value -> {:ok, value}
      end)

    assert {:error, %Error{code: :bad_item, path: [2], message: "Bad item"}} = result
    assert_error(Data.list([:ok | :bad_tail], &{:ok, &1}), :invalid_list)
  end

  @tag obligation: ["jido.agent.I1", "jido.agent.I22"]
  test "static authoring checks include Map keys" do
    assert_error(Data.static(%{self() => :ok}), :live_value)

    field = Zoi.integer()
    metadata = %{field.meta | metadata: %{self() => :ok}}
    schema = Zoi.object(%{value: %{field | meta: metadata}})

    assert_error(Data.schema(schema), :live_value)
  end

  @tag obligation: ["jido.agent.I9", "jido.agent.I22"]
  test "state schemas reject malformed fields and every conversion type" do
    malformed = struct(Zoi.Types.Map, fields: %{})
    assert_error(Data.schema(malformed), :invalid_schema)

    codec =
      Zoi.codec(Zoi.string(), Zoi.integer(),
        decode: fn value -> {:ok, String.to_integer(value)} end,
        encode: fn value -> {:ok, Integer.to_string(value)} end
      )

    assert {:error, %Error{code: :invalid_schema, message: message}} =
             Data.schema(Zoi.object(%{value: codec}))

    assert message != ""
  end

  @tag obligation: ["jido.agent.I8", "jido.agent.I22"]
  test "initialization cannot strip Map keys or convert list values" do
    assert_error(
      Data.parse_value(Zoi.object(%{}), %{unknown: 1}),
      :state_conversion
    )

    assert_error(
      Data.parse_value(Zoi.list(Zoi.integer(coerce: true)), ["1", 2]),
      :state_conversion
    )

    assert_error(
      Data.parse_value(
        Zoi.object(%{nested: Zoi.object(%{value: Zoi.integer(coerce: true)})}),
        %{nested: %{value: "1"}}
      ),
      :state_conversion
    )

    assert {:error, %Error{code: :invalid_state, message: message, details: %{issues: issues}}} =
             Data.parse_value(Zoi.integer(), "bad")

    assert message != ""
    assert [%Zoi.Error{} | _] = issues
  end

  @tag obligation: ["jido.agent.I9", "jido.agent.I22"]
  test "stored-state failures distinguish conversion from missing data" do
    assert_error(
      Data.complete(Zoi.object(%{value: Zoi.integer(coerce: true)}), %{value: "1"}),
      :state_conversion
    )

    assert {:error,
            %Error{
              code: :incomplete_state,
              message: message,
              details: %{issues: issues}
            }} = Data.complete(Zoi.object(%{value: Zoi.integer()}), %{})

    assert message != ""
    assert [%Zoi.Error{code: :required, path: [:value]} | _] = issues
  end

  @tag obligation: ["jido.agent.I21", "jido.agent.I22"]
  test "Signal paths reject malformed values with their source" do
    assert_error(Data.path("bad..path"), :invalid_path, %{path: "bad..path"})
    assert_error(Data.path(42), :invalid_path)
    assert_error(Data.exact("event.*"), :wildcard_type)
  end
end
