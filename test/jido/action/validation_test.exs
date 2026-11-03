defmodule JidoActionTest.Action.ValidationTest do
  use Covenant.Case, component: "jido_action.validation", async: true

  alias Jido.Action.Validation

  defmodule Params do
    @moduledoc false
    defstruct [:value]
  end

  defmodule ExtendedParams do
    defstruct [:value, :tag]
  end

  @tag obligation: ["jido_action.validation.I1", "jido_action.validation.I2"]
  test "schema transforms retain their chosen result and omit removed input fields" do
    struct_schema = Jido.Joi.struct(ExtendedParams, %{value: Jido.Joi.integer()}, coerce: true)
    input = %{value: 2, extra: :kept}

    transformed = Jido.Joi.transform(struct_schema, &%{&1 | tag: :added})

    assert {:ok, %{value: 2, tag: :added}} = Validation.parse(transformed, input, %{})

    removed =
      Jido.Joi.struct(Params, %{value: Jido.Joi.integer()})
      |> Jido.Joi.transform(fn params -> %{changed: params.value + 1} end)

    assert Validation.parse(removed, %Params{value: 2}, %{}) == {:ok, %{changed: 3}}

    scalar = Jido.Joi.transform(Jido.Joi.object(%{value: Jido.Joi.integer()}), & &1.value)
    assert {:ok, 2} = Validation.parse(scalar, %{value: 2}, %{})
    assert {:ok, 2} = Validation.parse_preserving_shape(scalar, %{value: 2}, %{})
  end

  @tag obligation: [
         "jido_action.validation.I1",
         "jido_action.validation.I2",
         "jido_action.validation.I3"
       ]
  test "struct roots follow Joi policies and project parsed structs to maps" do
    schema = Jido.Joi.struct(ExtendedParams, %{value: Jido.Joi.integer()}, coerce: false)

    assert Validation.parse(schema, %ExtendedParams{value: 2, tag: :kept}, %{}) ==
             {:ok, %{value: 2, tag: nil}}

    coercing = Jido.Joi.struct(Params, %{value: Jido.Joi.integer()}, coerce: true)

    assert Validation.parse(coercing, %{"value" => 2, "extra" => :kept}, %{}) ==
             {:ok, %{value: 2}}

    strict = Jido.Joi.struct(Params, %{value: Jido.Joi.integer()}, coerce: true, unrecognized_keys: :error)
    assert Validation.parse(strict, %{value: 2}, %{}) == {:ok, %{value: 2}}

    for {schema, data} <- [{schema, %{value: 2}}, {strict, %{value: 2, extra: :rejected}}] do
      assert {:error, expected} = Jido.Joi.parse(schema, data)
      assert {:error, error} = Validation.parse(schema, data, %{phase: :input})
      assert error.message == Jido.Joi.prettify_errors(expected)

      assert error.details == %{
               phase: :input,
               errors: Enum.map(expected, &Map.take(&1, [:path, :message, :code]))
             }
    end
  end

  @tag obligation: "jido_action.validation.I1"
  test "classification rejects foreign schemas, failed lazy builders and mixed codecs" do
    for value <- [%{}, %{inner: Jido.Joi.any()}, %URI{}, nil, :unsupported] do
      assert Jido.Joi.Schema.schema?(value) == false
      assert Jido.Joi.Schema.map_shaped?(value) == false
    end

    map = Jido.Joi.object(%{value: Jido.Joi.integer()})
    scalar = Jido.Joi.integer()
    unresolved = Jido.Joi.lazy(fn -> Jido.Joi.lazy(fn -> map end) end)
    failed = Jido.Joi.lazy(fn -> raise "builder failed" end)

    for lazy <- [unresolved, failed] do
      assert Jido.Joi.Schema.map_shaped?(lazy) == false
    end

    for {from, to} <- [{map, scalar}, {scalar, map}] do
      codec = Jido.Joi.codec(from, to, decode: &Function.identity/1, encode: &Function.identity/1)
      assert Jido.Joi.Schema.map_shaped?(codec) == false
    end
  end

  describe "parse/3" do
    @tag obligation: "jido_action.validation.I1"
    test "validates whole values for non-object Joi schemas" do
      assert {:ok, 3} = Validation.parse(Jido.Joi.integer(), 3, %{context: "Validation"})
    end

    @tag obligation: "jido_action.validation.I1"
    test "keeps Joi parsing behavior for map and struct schemas" do
      generic_map = Jido.Joi.map(Jido.Joi.string(), Jido.Joi.integer())

      assert {:error, %Jido.Error.ValidationError{}} =
               Validation.parse(generic_map, %{"value" => "bad"}, %{})

      coerced_object = Jido.Joi.object(%{value: Jido.Joi.integer()}, coerce: true)

      assert {:ok, %{value: 1}} =
               Validation.parse(coerced_object, %{"value" => 1, "extra" => 2}, %{})

      string_object = Jido.Joi.object(%{"value" => Jido.Joi.integer()})

      assert {:ok, %{"value" => 1}} =
               Validation.parse(string_object, %{"value" => 1}, %{})

      struct_schema = Jido.Joi.struct(Params, %{value: Jido.Joi.integer()})

      assert {:ok, %{value: 1}} =
               Validation.parse(struct_schema, %Params{value: 1}, %{})
    end

    @tag obligation: "jido_action.validation.I1"
    test "keeps struct refinements and returns the complete parsed struct map" do
      schema =
        Jido.Joi.struct(URI, %{scheme: Jido.Joi.string()}, coerce: true)
        |> Jido.Joi.refine(fn value ->
          if is_struct(value, URI), do: :ok, else: {:error, "expected URI struct"}
        end)

      assert {:ok, result} =
               Validation.parse(schema, %{scheme: "https", extra: "kept"}, %{})

      assert {:ok, parsed} = Jido.Joi.parse(schema, %{scheme: "https", extra: "kept"})
      assert result == Map.from_struct(parsed)
      assert result.scheme == "https"
      refute Map.has_key?(result, :extra)
    end

    @tag obligation: "jido_action.validation.I2"
    test "uses explicit Joi preservation policies in nested and wrapped schemas" do
      nested_schema =
        Jido.Joi.object(%{
          user: Jido.Joi.object(%{name: Jido.Joi.string()}, unrecognized_keys: :preserve)
        })

      assert {:ok, %{user: %{id: 7, name: "Ada"}}} =
               Validation.parse(
                 nested_schema,
                 %{trace: "trace", user: %{id: 7, name: "Ada"}},
                 %{}
               )

      object_schema =
        Jido.Joi.object(%{value: Jido.Joi.integer()}, unrecognized_keys: :preserve)

      codec_schema =
        Jido.Joi.codec(object_schema, object_schema,
          decode: &Function.identity/1,
          encode: &Function.identity/1
        )

      for wrapped_schema <- [
            Jido.Joi.default(object_schema, %{value: 0}),
            Jido.Joi.nullable(object_schema),
            Jido.Joi.lazy(fn -> object_schema end),
            codec_schema
          ] do
        assert {:ok, %{extra: "kept", value: 1}} =
                 Validation.parse(
                   wrapped_schema,
                   %{extra: "kept", value: 1},
                   %{}
                 )
      end
    end

    @tag obligation: "jido_action.validation.I2"
    test "honors declared Joi unknown-key policies at the root" do
      default_strip = Jido.Joi.object(%{name: Jido.Joi.string()})

      assert {:ok, %{name: "Ada"}} =
               Validation.parse(default_strip, %{extra: true, name: "Ada"}, %{})

      nested_default = Jido.Joi.object(%{user: Jido.Joi.object(%{name: Jido.Joi.string()})})

      assert {:ok, validated_nested} =
               Validation.parse(
                 nested_default,
                 %{user: %{id: 7, name: "Ada"}},
                 %{}
               )

      assert validated_nested == %{user: %{name: "Ada"}}

      strict = Jido.Joi.object(%{name: Jido.Joi.string()}, unrecognized_keys: :error)

      assert {:error, %Jido.Error.ValidationError{}} =
               Validation.parse(strict, %{extra: true, name: "Ada"}, %{})

      strict_struct =
        Jido.Joi.struct(Params, %{value: Jido.Joi.integer()},
          coerce: true,
          unrecognized_keys: :error
        )

      assert {:error, %Jido.Error.ValidationError{}} =
               Validation.parse(strict_struct, %{extra: true, value: 1}, %{})

      typed_unknowns =
        Jido.Joi.object(%{name: Jido.Joi.string()},
          unrecognized_keys: {:preserve, {Jido.Joi.atom(), Jido.Joi.integer()}}
        )

      assert {:ok, %{extra: 1, name: "Ada"}} =
               Validation.parse(typed_unknowns, %{extra: 1, name: "Ada"}, %{})

      assert {:error, %Jido.Error.ValidationError{}} =
               Validation.parse(
                 typed_unknowns,
                 %{extra: "not an integer", name: "Ada"},
                 %{}
               )
    end
  end

  @tag obligation: ["jido_action.validation.I1", "jido_action.validation.I2"]
  test "matches Joi results across direct, nested, and wrapped object policies" do
    strip = Jido.Joi.object(%{name: Jido.Joi.string()})
    preserve = Jido.Joi.object(%{name: Jido.Joi.string()}, unrecognized_keys: :preserve)
    strict = Jido.Joi.object(%{name: Jido.Joi.string()}, unrecognized_keys: :error)

    typed =
      Jido.Joi.object(%{name: Jido.Joi.string()},
        unrecognized_keys: {:preserve, {Jido.Joi.atom(), Jido.Joi.integer()}}
      )

    nested = Jido.Joi.object(%{user: strip}, unrecognized_keys: :preserve)
    wrapped = Jido.Joi.nullable(strip)

    coercing =
      Jido.Joi.object(%{count: Jido.Joi.integer(coerce: true)}, coerce: true)

    cases = [
      {strip, %{extra: true, name: "Ada"}},
      {preserve, %{extra: true, name: "Ada"}},
      {strict, %{extra: true, name: "Ada"}},
      {typed, %{extra: 1, name: "Ada"}},
      {typed, %{extra: "bad", name: "Ada"}},
      {nested, %{trace: "kept", user: %{extra: true, name: "Ada"}}},
      {wrapped, %{extra: true, name: "Ada"}},
      {Jido.Joi.default(strip, %{name: "default"}), nil},
      {Jido.Joi.union([strip, Jido.Joi.string()]), %{extra: true, name: "Ada"}},
      {coercing, %{"count" => "2", "extra" => true}}
    ]

    Enum.each(cases, fn {schema, input} -> assert_matches_joi(schema, input) end)
  end

  @tag obligation: "jido_action.validation.I1"
  test "validates fieldless struct schemas without schema traversal" do
    fieldless = Jido.Joi.struct(Params)

    assert {:ok, %{value: 1}} =
             Validation.parse(fieldless, %Params{value: 1}, %{})

    nested = Jido.Joi.object(%{params: fieldless})
    input = %{extra: true, params: %Params{value: 1}}

    assert {:ok, %{params: %Params{value: 1}}} = Validation.parse(nested, input, %{})
  end

  describe "parse_preserving_shape/3" do
    @tag obligation: "jido_action.validation.I1"
    test "keeps structs and plain values in their validated shape" do
      schema = Jido.Joi.struct(Params, %{value: Jido.Joi.integer()})

      assert {:ok, %Params{value: 1}} =
               Validation.parse_preserving_shape(schema, %Params{value: 1}, %{})

      assert {:ok, 1} = Validation.parse_preserving_shape(Jido.Joi.integer(), 1, %{})

      assert {:ok, %{value: 1}} =
               Validation.parse_preserving_shape(
                 Jido.Joi.object(%{value: Jido.Joi.integer()}),
                 %{value: 1, extra: true},
                 %{}
               )

      assert {:ok, %{value: 1, extra: true}} =
               Validation.parse_preserving_shape(
                 Jido.Joi.object(%{value: Jido.Joi.integer()}, unrecognized_keys: :preserve),
                 %{value: 1, extra: true},
                 %{}
               )
    end

    @tag obligation: "jido_action.validation.I3"
    test "returns validation and unsupported-schema errors" do
      assert {:error, error} =
               Validation.parse_preserving_shape(Jido.Joi.integer(), "bad", %{phase: :test})

      assert error.details.phase == :test
      assert is_list(error.details.errors)

      assert {:error, error} =
               Validation.parse_preserving_shape(:invalid, %{}, %{phase: :test})

      assert Exception.message(error) == "Unsupported schema type"

      assert {:error, error} =
               Validation.parse_preserving_shape([], %{}, %{phase: :test})

      assert Exception.message(error) == "Unsupported schema type"
    end
  end

  @tag obligation: "jido_action.validation.I2"
  test "uses declared Joi policies inside collection and combination schemas" do
    cat =
      Jido.Joi.object(%{type: Jido.Joi.literal("cat"), name: Jido.Joi.string()},
        unrecognized_keys: :preserve
      )

    dog =
      Jido.Joi.object(%{type: Jido.Joi.literal("dog"), name: Jido.Joi.string()},
        unrecognized_keys: :preserve
      )

    schema =
      Jido.Joi.object(%{
        pets: Jido.Joi.array(Jido.Joi.discriminated_union(:type, [cat, dog])),
        pair:
          Jido.Joi.tuple(
            {Jido.Joi.object(%{value: Jido.Joi.integer()}, unrecognized_keys: :preserve), Jido.Joi.integer()}
          ),
        merged:
          Jido.Joi.intersection([
            Jido.Joi.object(%{left: Jido.Joi.integer()}, unrecognized_keys: :preserve),
            Jido.Joi.object(%{right: Jido.Joi.integer()}, unrecognized_keys: :preserve)
          ])
      })

    value = %{
      pets: [%{type: "cat", name: "Mochi", extra: true}],
      pair: {%{value: 1, extra: true}, 2},
      merged: %{left: 1, right: 2, extra: true}
    }

    assert {:ok, validated} = assert_matches_joi(schema, value)
    assert get_in(validated, [:pets, Access.at(0), :extra])
    assert validated.pair |> elem(0) |> Map.fetch!(:extra)
  end

  @tag obligation: "jido_action.validation.I2"
  test "uses a declared Joi policy inside map sets" do
    schema =
      Jido.Joi.object(%{
        users: Jido.Joi.map_set(Jido.Joi.object(%{name: Jido.Joi.string()}, unrecognized_keys: :preserve))
      })

    input = %{users: MapSet.new([%{id: 7, name: "Ada"}])}

    assert {:ok, %{users: users}} = Validation.parse(schema, input, %{})
    assert MapSet.member?(users, %{id: 7, name: "Ada"})
  end

  @tag obligation: "jido_action.validation.I3"
  test "converts raised and thrown schema failures to structured errors" do
    raising = Jido.Joi.lazy(fn -> raise "schema boom" end)
    throwing = Jido.Joi.lazy(fn -> throw(:schema_boom) end)

    assert {:error, raised} = Validation.parse(raising, %{}, %{phase: :raised})
    assert Exception.message(raised) == "schema validation failed"
    assert raised.details.exception == RuntimeError
    assert raised.details.phase == :raised

    assert {:error, thrown} = Validation.parse(throwing, %{}, %{phase: :thrown})
    assert Exception.message(thrown) == "schema validation failed"
    assert thrown.details.failure_kind == :throw
    assert thrown.details.phase == :thrown
  end

  @tag obligation: "jido_action.validation.I1"
  test "classifies Action-compatible schema containers" do
    map = Jido.Joi.object(%{value: Jido.Joi.integer()})
    any = Jido.Joi.any()
    literal_map = Jido.Joi.literal(%{value: 1})
    default = Jido.Joi.default(map, %{value: 0})
    union = Jido.Joi.union([map, Jido.Joi.integer()])
    intersection = Jido.Joi.intersection([map, map])

    codec =
      Jido.Joi.codec(map, map,
        decode: &Function.identity/1,
        encode: &Function.identity/1
      )

    discriminated =
      Jido.Joi.discriminated_union(:type, [
        Jido.Joi.object(%{type: Jido.Joi.literal("one")}),
        Jido.Joi.object(%{type: Jido.Joi.literal("two")})
      ])

    for schema <- [
          map,
          Jido.Joi.struct(Params, %{value: Jido.Joi.integer()}),
          any,
          literal_map,
          default,
          union,
          intersection,
          codec,
          discriminated,
          Jido.Joi.lazy(fn -> map end),
          Jido.Joi.lazy({__MODULE__, :map_schema, []})
        ] do
      assert Jido.Joi.Schema.map_shaped?(schema)
    end

    refute Jido.Joi.Schema.map_shaped?(Jido.Joi.integer())
    refute Jido.Joi.Schema.map_shaped?(Jido.Joi.literal(:not_a_map))
    refute Jido.Joi.Schema.map_shaped?(Jido.Joi.union([Jido.Joi.integer(), Jido.Joi.string()]))
    refute Jido.Joi.Schema.map_shaped?(Jido.Joi.intersection([map, Jido.Joi.integer()]))
  end

  def map_schema, do: Jido.Joi.object(%{value: Jido.Joi.integer()})

  @tag obligation: "jido_action.validation.I1"
  test "defaults do not make scalar schemas map-compatible" do
    for schema <- [Jido.Joi.integer(), Jido.Joi.string(), Jido.Joi.literal(:not_a_map)] do
      refute Jido.Joi.Schema.map_shaped?(Jido.Joi.default(schema, %{value: 0}))
    end
  end

  defp assert_matches_joi(schema, input) do
    result = Validation.parse(schema, input, %{})

    case Jido.Joi.parse(schema, input) do
      {:ok, expected} ->
        expected = if is_struct(expected), do: Map.from_struct(expected), else: expected
        assert result == {:ok, expected}

      {:error, errors} ->
        assert {:error, error} = result
        assert error.message == Jido.Joi.prettify_errors(errors)
        assert error.details.errors == Enum.map(errors, &Map.take(&1, [:path, :message, :code]))
    end

    result
  end
end
