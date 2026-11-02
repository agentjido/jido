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
    struct_schema = Zoi.struct(ExtendedParams, %{value: Zoi.integer()}, coerce: true)
    input = %{value: 2, extra: :kept}

    transformed = Zoi.transform(struct_schema, &%{&1 | tag: :added})

    assert {:ok, %{value: 2, tag: :added}} = Validation.parse(transformed, input, %{})

    removed =
      Zoi.struct(Params, %{value: Zoi.integer()})
      |> Zoi.transform(fn params -> %{changed: params.value + 1} end)

    assert Validation.parse(removed, %Params{value: 2}, %{}) == {:ok, %{changed: 3}}

    scalar = Zoi.transform(Zoi.object(%{value: Zoi.integer()}), & &1.value)
    assert {:ok, 2} = Validation.parse(scalar, %{value: 2}, %{})
    assert {:ok, 2} = Validation.parse_preserving_shape(scalar, %{value: 2}, %{})
  end

  @tag obligation: [
         "jido_action.validation.I1",
         "jido_action.validation.I2",
         "jido_action.validation.I3"
       ]
  test "struct roots follow Zoi policies and project parsed structs to maps" do
    schema = Zoi.struct(ExtendedParams, %{value: Zoi.integer()}, coerce: false)

    assert Validation.parse(schema, %ExtendedParams{value: 2, tag: :kept}, %{}) ==
             {:ok, %{value: 2, tag: nil}}

    coercing = Zoi.struct(Params, %{value: Zoi.integer()}, coerce: true)

    assert Validation.parse(coercing, %{"value" => 2, "extra" => :kept}, %{}) ==
             {:ok, %{value: 2}}

    strict = Zoi.struct(Params, %{value: Zoi.integer()}, coerce: true, unrecognized_keys: :error)
    assert Validation.parse(strict, %{value: 2}, %{}) == {:ok, %{value: 2}}

    for {schema, data} <- [{schema, %{value: 2}}, {strict, %{value: 2, extra: :rejected}}] do
      assert {:error, expected} = Zoi.parse(schema, data)
      assert {:error, error} = Validation.parse(schema, data, %{phase: :input})
      assert error.message == Zoi.prettify_errors(expected)

      assert error.details == %{
               phase: :input,
               errors: Enum.map(expected, &Map.take(&1, [:path, :message, :code]))
             }
    end
  end

  @tag obligation: "jido_action.validation.I1"
  test "classification rejects foreign schemas, failed lazy builders and mixed codecs" do
    for value <- [%{}, %{inner: Zoi.any()}, %URI{}, nil, :unsupported] do
      assert Validation.zoi_schema?(value) == false
      assert Validation.map_schema?(value) == false
    end

    map = Zoi.object(%{value: Zoi.integer()})
    scalar = Zoi.integer()
    unresolved = Zoi.lazy(fn -> Zoi.lazy(fn -> map end) end)
    failed = Zoi.lazy(fn -> raise "builder failed" end)

    for lazy <- [unresolved, failed] do
      assert Validation.map_schema?(lazy) == false
    end

    for {from, to} <- [{map, scalar}, {scalar, map}] do
      codec = Zoi.codec(from, to, decode: &Function.identity/1, encode: &Function.identity/1)
      assert Validation.map_schema?(codec) == false
    end

    legacy_default = %{__struct__: Zoi.Types.Default, inner: map}
    assert Validation.map_schema?(legacy_default)
  end

  describe "parse/3" do
    @tag obligation: "jido_action.validation.I1"
    test "validates whole values for non-object Zoi schemas" do
      assert {:ok, 3} = Validation.parse(Zoi.integer(), 3, %{context: "Validation"})
    end

    @tag obligation: "jido_action.validation.I1"
    test "keeps Zoi parsing behavior for map and struct schemas" do
      generic_map = Zoi.map(Zoi.string(), Zoi.integer())

      assert {:error, %Jido.Action.Error.InvalidInputError{}} =
               Validation.parse(generic_map, %{"value" => "bad"}, %{})

      coerced_object = Zoi.object(%{value: Zoi.integer()}, coerce: true)

      assert {:ok, %{value: 1}} =
               Validation.parse(coerced_object, %{"value" => 1, "extra" => 2}, %{})

      string_object = Zoi.object(%{"value" => Zoi.integer()})

      assert {:ok, %{"value" => 1}} =
               Validation.parse(string_object, %{"value" => 1}, %{})

      struct_schema = Zoi.struct(Params, %{value: Zoi.integer()})

      assert {:ok, %{value: 1}} =
               Validation.parse(struct_schema, %Params{value: 1}, %{})
    end

    @tag obligation: "jido_action.validation.I1"
    test "keeps struct refinements and returns the complete parsed struct map" do
      schema =
        Zoi.struct(URI, %{scheme: Zoi.string()}, coerce: true)
        |> Zoi.refine(fn value ->
          if is_struct(value, URI), do: :ok, else: {:error, "expected URI struct"}
        end)

      assert {:ok, result} =
               Validation.parse(schema, %{scheme: "https", extra: "kept"}, %{})

      assert {:ok, parsed} = Zoi.parse(schema, %{scheme: "https", extra: "kept"})
      assert result == Map.from_struct(parsed)
      assert result.scheme == "https"
      refute Map.has_key?(result, :extra)
    end

    @tag obligation: "jido_action.validation.I2"
    test "uses explicit Zoi preservation policies in nested and wrapped schemas" do
      nested_schema =
        Zoi.object(%{
          user: Zoi.object(%{name: Zoi.string()}, unrecognized_keys: :preserve)
        })

      assert {:ok, %{user: %{id: 7, name: "Ada"}}} =
               Validation.parse(
                 nested_schema,
                 %{trace: "trace", user: %{id: 7, name: "Ada"}},
                 %{}
               )

      object_schema =
        Zoi.object(%{value: Zoi.integer()}, unrecognized_keys: :preserve)

      codec_schema =
        Zoi.codec(object_schema, object_schema,
          decode: &Function.identity/1,
          encode: &Function.identity/1
        )

      for wrapped_schema <- [
            Zoi.default(object_schema, %{value: 0}),
            Zoi.nullable(object_schema),
            Zoi.lazy(fn -> object_schema end),
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
    test "honors declared Zoi unknown-key policies at the root" do
      default_strip = Zoi.object(%{name: Zoi.string()})

      assert {:ok, %{name: "Ada"}} =
               Validation.parse(default_strip, %{extra: true, name: "Ada"}, %{})

      nested_default = Zoi.object(%{user: Zoi.object(%{name: Zoi.string()})})

      assert {:ok, validated_nested} =
               Validation.parse(
                 nested_default,
                 %{user: %{id: 7, name: "Ada"}},
                 %{}
               )

      assert validated_nested == %{user: %{name: "Ada"}}

      strict = Zoi.object(%{name: Zoi.string()}, unrecognized_keys: :error)

      assert {:error, %Jido.Action.Error.InvalidInputError{}} =
               Validation.parse(strict, %{extra: true, name: "Ada"}, %{})

      strict_struct =
        Zoi.struct(Params, %{value: Zoi.integer()},
          coerce: true,
          unrecognized_keys: :error
        )

      assert {:error, %Jido.Action.Error.InvalidInputError{}} =
               Validation.parse(strict_struct, %{extra: true, value: 1}, %{})

      typed_unknowns =
        Zoi.object(%{name: Zoi.string()},
          unrecognized_keys: {:preserve, {Zoi.atom(), Zoi.integer()}}
        )

      assert {:ok, %{extra: 1, name: "Ada"}} =
               Validation.parse(typed_unknowns, %{extra: 1, name: "Ada"}, %{})

      assert {:error, %Jido.Action.Error.InvalidInputError{}} =
               Validation.parse(
                 typed_unknowns,
                 %{extra: "not an integer", name: "Ada"},
                 %{}
               )
    end
  end

  @tag obligation: ["jido_action.validation.I1", "jido_action.validation.I2"]
  test "matches Zoi results across direct, nested, and wrapped object policies" do
    strip = Zoi.object(%{name: Zoi.string()})
    preserve = Zoi.object(%{name: Zoi.string()}, unrecognized_keys: :preserve)
    strict = Zoi.object(%{name: Zoi.string()}, unrecognized_keys: :error)

    typed =
      Zoi.object(%{name: Zoi.string()},
        unrecognized_keys: {:preserve, {Zoi.atom(), Zoi.integer()}}
      )

    nested = Zoi.object(%{user: strip}, unrecognized_keys: :preserve)
    wrapped = Zoi.nullable(strip)

    coercing =
      Zoi.object(%{count: Zoi.integer(coerce: true)}, coerce: true)

    cases = [
      {strip, %{extra: true, name: "Ada"}},
      {preserve, %{extra: true, name: "Ada"}},
      {strict, %{extra: true, name: "Ada"}},
      {typed, %{extra: 1, name: "Ada"}},
      {typed, %{extra: "bad", name: "Ada"}},
      {nested, %{trace: "kept", user: %{extra: true, name: "Ada"}}},
      {wrapped, %{extra: true, name: "Ada"}},
      {Zoi.default(strip, %{name: "default"}), nil},
      {Zoi.union([strip, Zoi.string()]), %{extra: true, name: "Ada"}},
      {coercing, %{"count" => "2", "extra" => true}}
    ]

    Enum.each(cases, fn {schema, input} -> assert_matches_zoi(schema, input) end)
  end

  @tag obligation: "jido_action.validation.I1"
  test "validates fieldless struct schemas without schema traversal" do
    fieldless = Zoi.struct(Params)

    assert {:ok, %{value: 1}} =
             Validation.parse(fieldless, %Params{value: 1}, %{})

    nested = Zoi.object(%{params: fieldless})
    input = %{extra: true, params: %Params{value: 1}}

    assert {:ok, %{params: %Params{value: 1}}} = Validation.parse(nested, input, %{})
  end

  describe "parse_preserving_shape/3" do
    @tag obligation: "jido_action.validation.I1"
    test "keeps structs and plain values in their validated shape" do
      schema = Zoi.struct(Params, %{value: Zoi.integer()})

      assert {:ok, %Params{value: 1}} =
               Validation.parse_preserving_shape(schema, %Params{value: 1}, %{})

      assert {:ok, 1} = Validation.parse_preserving_shape(Zoi.integer(), 1, %{})

      assert {:ok, %{value: 1}} =
               Validation.parse_preserving_shape(
                 Zoi.object(%{value: Zoi.integer()}),
                 %{value: 1, extra: true},
                 %{}
               )

      assert {:ok, %{value: 1, extra: true}} =
               Validation.parse_preserving_shape(
                 Zoi.object(%{value: Zoi.integer()}, unrecognized_keys: :preserve),
                 %{value: 1, extra: true},
                 %{}
               )
    end

    @tag obligation: "jido_action.validation.I3"
    test "returns validation and unsupported-schema errors" do
      assert {:error, error} =
               Validation.parse_preserving_shape(Zoi.integer(), "bad", %{phase: :test})

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
  test "uses declared Zoi policies inside collection and combination schemas" do
    cat =
      Zoi.object(%{type: Zoi.literal("cat"), name: Zoi.string()},
        unrecognized_keys: :preserve
      )

    dog =
      Zoi.object(%{type: Zoi.literal("dog"), name: Zoi.string()},
        unrecognized_keys: :preserve
      )

    schema =
      Zoi.object(%{
        pets: Zoi.array(Zoi.discriminated_union(:type, [cat, dog])),
        pair: Zoi.tuple({Zoi.object(%{value: Zoi.integer()}, unrecognized_keys: :preserve), Zoi.integer()}),
        merged:
          Zoi.intersection([
            Zoi.object(%{left: Zoi.integer()}, unrecognized_keys: :preserve),
            Zoi.object(%{right: Zoi.integer()}, unrecognized_keys: :preserve)
          ])
      })

    value = %{
      pets: [%{type: "cat", name: "Mochi", extra: true}],
      pair: {%{value: 1, extra: true}, 2},
      merged: %{left: 1, right: 2, extra: true}
    }

    assert {:ok, validated} = assert_matches_zoi(schema, value)
    assert get_in(validated, [:pets, Access.at(0), :extra])
    assert validated.pair |> elem(0) |> Map.fetch!(:extra)
  end

  @tag obligation: "jido_action.validation.I2"
  test "uses a declared Zoi policy inside map sets" do
    schema =
      Zoi.object(%{
        users: Zoi.map_set(Zoi.object(%{name: Zoi.string()}, unrecognized_keys: :preserve))
      })

    input = %{users: MapSet.new([%{id: 7, name: "Ada"}])}

    assert {:ok, %{users: users}} = Validation.parse(schema, input, %{})
    assert MapSet.member?(users, %{id: 7, name: "Ada"})
  end

  @tag obligation: "jido_action.validation.I3"
  test "converts raised and thrown schema failures to structured errors" do
    raising = Zoi.lazy(fn -> raise "schema boom" end)
    throwing = Zoi.lazy(fn -> throw(:schema_boom) end)

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
    map = Zoi.object(%{value: Zoi.integer()})
    any = Zoi.any()
    literal_map = Zoi.literal(%{value: 1})
    default = Zoi.default(map, %{value: 0})
    union = Zoi.union([map, Zoi.integer()])
    intersection = Zoi.intersection([map, map])

    codec =
      Zoi.codec(map, map,
        decode: &Function.identity/1,
        encode: &Function.identity/1
      )

    discriminated =
      Zoi.discriminated_union(:type, [
        Zoi.object(%{type: Zoi.literal("one")}),
        Zoi.object(%{type: Zoi.literal("two")})
      ])

    for schema <- [
          map,
          Zoi.struct(Params, %{value: Zoi.integer()}),
          any,
          literal_map,
          default,
          union,
          intersection,
          codec,
          discriminated,
          Zoi.lazy(fn -> map end),
          Zoi.lazy({__MODULE__, :map_schema, []})
        ] do
      assert Validation.map_schema?(schema)
    end

    refute Validation.map_schema?(Zoi.integer())
    refute Validation.map_schema?(Zoi.literal(:not_a_map))
    refute Validation.map_schema?(Zoi.union([Zoi.integer(), Zoi.string()]))
    refute Validation.map_schema?(Zoi.intersection([map, Zoi.integer()]))
  end

  def map_schema, do: Zoi.object(%{value: Zoi.integer()})

  @tag obligation: "jido_action.validation.I1"
  test "defaults do not make scalar schemas map-compatible" do
    for schema <- [Zoi.integer(), Zoi.string(), Zoi.literal(:not_a_map)] do
      refute Validation.map_schema?(Zoi.default(schema, %{value: 0}))
    end
  end

  defp assert_matches_zoi(schema, input) do
    result = Validation.parse(schema, input, %{})

    case Zoi.parse(schema, input) do
      {:ok, expected} ->
        expected = if is_struct(expected), do: Map.from_struct(expected), else: expected
        assert result == {:ok, expected}

      {:error, errors} ->
        assert {:error, error} = result
        assert error.message == Zoi.prettify_errors(errors)
        assert error.details.errors == Enum.map(errors, &Map.take(&1, [:path, :message, :code]))
    end

    result
  end
end
