defmodule JidoTest.Agent.StateTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.State

  describe "validate_schema/2" do
    test "accepts field-based Zoi map schemas and the empty sentinel" do
      assert :ok = State.validate_schema(Zoi.object(%{name: Zoi.string()}))
      assert :ok = State.validate_schema([])
    end

    test "rejects non-map and open map schemas" do
      assert {:error, "must be a field-based Zoi map schema"} =
               State.validate_schema(Zoi.string())

      assert {:error, "must be a field-based Zoi map schema"} =
               State.validate_schema(Zoi.map())
    end
  end

  describe "merge/2" do
    test "merges keyword list into current state" do
      current = %{a: 1, b: 2}
      result = State.merge(current, c: 3, d: 4)

      assert result == %{a: 1, b: 2, c: 3, d: 4}
    end

    test "merges map into current state" do
      current = %{a: 1, b: 2}
      result = State.merge(current, %{c: 3, d: 4})

      assert result == %{a: 1, b: 2, c: 3, d: 4}
    end

    test "deep merges nested maps" do
      current = %{config: %{a: 1, b: 2}}
      result = State.merge(current, %{config: %{b: 3, c: 4}})

      assert result == %{config: %{a: 1, b: 3, c: 4}}
    end

    test "deep merges nested keyword lists" do
      current = %{config: [a: 1, b: [x: 10, y: 9]]}
      result = State.merge(current, %{config: [b: [y: 20, z: 30], c: 4]})

      assert result == %{config: [a: 1, b: [x: 10, y: 20, z: 30], c: 4]}
    end

    test "preserves keyword list when override is empty list" do
      current = %{config: [a: 1, b: 2]}
      result = State.merge(current, %{config: []})

      assert result == %{config: [a: 1, b: 2]}
    end

    test "overwrites non-map values" do
      current = %{value: 1}
      result = State.merge(current, %{value: 2})

      assert result == %{value: 2}
    end

    test "replaces structs instead of merging them as maps" do
      current = %{endpoint: %URI{scheme: "http", host: "example.com"}}
      result = State.merge(current, %{endpoint: %{scheme: "https"}})

      assert result == %{endpoint: %{scheme: "https"}}
    end
  end

  describe "validate/3" do
    test "returns state unchanged for empty schema" do
      state = %{a: 1, b: 2}

      assert {:ok, ^state} = State.validate(state, [])
    end

    test "validates state against a Zoi schema" do
      schema =
        Zoi.object(%{
          name: Zoi.string(),
          count: Zoi.integer() |> Zoi.default(0)
        })

      state = %{name: "test", count: 5}

      assert {:ok, validated} = State.validate(state, schema)
      assert validated.name == "test"
      assert validated.count == 5
    end

    test "preserves extra fields in non-strict mode" do
      schema = Zoi.object(%{name: Zoi.string()})
      state = %{name: "test", extra: "field"}

      assert {:ok, validated} = State.validate(state, schema)
      assert validated.extra == "field"
    end

    test "removes extra fields in strict mode" do
      schema = Zoi.object(%{name: Zoi.string()})
      state = %{name: "test", extra: "field"}

      assert {:ok, validated} = State.validate(state, schema, strict: true)
      refute Map.has_key?(validated, :extra)
    end

    test "returns error for invalid state" do
      schema = Zoi.object(%{count: Zoi.integer()})
      state = %{count: "not an integer"}

      assert {:error, _} = State.validate(state, schema)
    end

    test "applies defaults from schema" do
      schema = Zoi.object(%{count: Zoi.integer() |> Zoi.default(10)})
      state = %{}

      assert {:ok, validated} = State.validate(state, schema)
      assert validated.count == 10
    end

    test "validates against Zoi schema" do
      zoi_schema = Zoi.object(%{status: Zoi.atom(), count: Zoi.integer()})
      state = %{status: :active, count: 5}

      assert {:ok, validated} = State.validate(state, zoi_schema)
      assert validated.status == :active
      assert validated.count == 5
    end

    test "Zoi schema strict mode removes extra fields" do
      zoi_schema = Zoi.object(%{status: Zoi.atom()})
      state = %{status: :active, extra: "data"}

      assert {:ok, validated} = State.validate(state, zoi_schema, strict: true)
      refute Map.has_key?(validated, :extra)
    end
  end

  describe "defaults_from_schema/1" do
    test "returns empty map for empty schema" do
      assert State.defaults_from_schema([]) == %{}
    end

    test "extracts defaults from a Zoi schema" do
      schema =
        Zoi.object(%{
          name: Zoi.string() |> Zoi.default("default_name"),
          count: Zoi.integer() |> Zoi.default(0),
          status: Zoi.atom() |> Zoi.optional()
        })

      defaults = State.defaults_from_schema(schema)

      assert defaults == %{name: "default_name", count: 0}
    end

    test "extracts defaults from Zoi schema" do
      zoi_schema = Zoi.object(%{status: Zoi.atom() |> Zoi.default(:idle)})

      assert State.defaults_from_schema(zoi_schema) == %{status: :idle}
    end

    test "only includes keys with defaults" do
      schema =
        Zoi.object(%{
          with_default: Zoi.string() |> Zoi.default("value"),
          without_default: Zoi.integer()
        })

      defaults = State.defaults_from_schema(schema)

      assert Map.has_key?(defaults, :with_default)
      refute Map.has_key?(defaults, :without_default)
    end
  end
end
