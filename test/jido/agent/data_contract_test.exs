defmodule Jido.Agent.ValidationDataContractTest do
  use Covenant.Case, component: "jido.agent", async: true

  alias Jido.Agent.Schema
  alias Jido.Error.ValidationError, as: Error

  defp assert_error(result, code, details \\ %{}) do
    assert {:error, %Error{code: ^code, message: message, details: ^details}} = result
    assert message != ""
  end

  @tag obligation: ["jido.agent.I3", "jido.agent.I7", "jido.agent.I22"]
  test "scalar authoring validators keep their exact boundaries" do
    assert :ok = Schema.nonempty("a")

    for value <- [nil, true, false] do
      assert_error(Schema.name(value), :invalid_name)
    end

    assert_error(Schema.nonempty(""), :invalid_string)
    assert_error(Schema.positive(0), :invalid_positive)
  end

  @tag obligation: ["jido.agent.I3", "jido.agent.I22"]
  test "collection errors retain the failed field, declaration, and index" do
    assert_error(Schema.fields(%{bad: 1}, []), :unknown_fields, %{keys: [:bad]})
    assert_error(Schema.unique([:a, :a], & &1), :duplicate, %{values: [:a, :a]})

    result =
      Schema.list([:ok, :ok, :bad], fn
        :bad -> Jido.Error.validation_result(:bad_item, [], "Bad item")
        value -> {:ok, value}
      end)

    assert {:error, %Error{code: :bad_item, path: [2], message: "Bad item"}} = result
    assert_error(Schema.list([:ok | :bad_tail], &{:ok, &1}), :invalid_list)
  end

  @tag obligation: ["jido.agent.I1", "jido.agent.I22"]
  test "static authoring checks include Map keys" do
    assert_error(Schema.static(%{self() => :ok}), :live_value)

    field = Jido.Joi.integer()
    metadata = %{field.meta | metadata: %{self() => :ok}}
    schema = Jido.Joi.object(%{value: %{field | meta: metadata}})

    assert_error(Schema.schema(schema), :live_value)
  end

  @tag obligation: ["jido.agent.I9", "jido.agent.I22"]
  test "state schemas reject malformed fields and every conversion type" do
    malformed = Map.put(Jido.Joi.map(), :fields, %{})
    assert_error(Schema.schema(malformed), :invalid_schema)

    codec =
      Jido.Joi.codec(Jido.Joi.string(), Jido.Joi.integer(),
        decode: fn value -> {:ok, String.to_integer(value)} end,
        encode: fn value -> {:ok, Integer.to_string(value)} end
      )

    assert {:error, %Error{code: :invalid_schema, message: message}} =
             Schema.schema(Jido.Joi.object(%{value: codec}))

    assert message != ""
  end

  @tag obligation: ["jido.agent.I8", "jido.agent.I22"]
  test "initialization preserves open Map keys but cannot convert list values" do
    assert {:ok, %{unknown: 1}} =
             Schema.parse_value(Jido.Joi.object(%{}), %{unknown: 1})

    assert_error(
      Schema.parse_value(Jido.Joi.list(Jido.Joi.integer(coerce: true)), ["1", 2]),
      :state_conversion
    )

    assert_error(
      Schema.parse_value(
        Jido.Joi.object(%{nested: Jido.Joi.object(%{value: Jido.Joi.integer(coerce: true)})}),
        %{nested: %{value: "1"}}
      ),
      :state_conversion
    )

    assert {:error, %Error{code: :invalid_state, message: message, details: %{issues: issues}}} =
             Schema.parse_value(Jido.Joi.integer(), "bad")

    assert message != ""
    assert [%{} | _] = issues
  end

  @tag obligation: ["jido.agent.I9", "jido.agent.I22"]
  test "stored-state failures distinguish conversion from missing data" do
    assert_error(
      Schema.complete(Jido.Joi.object(%{value: Jido.Joi.integer(coerce: true)}), %{value: "1"}),
      :state_conversion
    )

    assert {:error,
            %Error{
              code: :incomplete_state,
              message: message,
              details: %{issues: issues}
            }} = Schema.complete(Jido.Joi.object(%{value: Jido.Joi.integer()}), %{})

    assert message != ""
    assert [%{code: :required, path: [:value]} | _] = issues
  end

  @tag obligation: ["jido.agent.I21", "jido.agent.I22"]
  test "Signal paths reject malformed values with their source" do
    assert_error(Schema.path("bad..path"), :invalid_path, %{path: "bad..path"})
    assert_error(Schema.path(42), :invalid_path)
    assert_error(Schema.exact("event.*"), :wildcard_type)
  end
end
