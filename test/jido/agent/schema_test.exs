defmodule JidoTest.Agent.SchemaTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Schema

  defmodule DefaultAgent do
    use Jido.Agent,
      name: "zoi_default_agent",
      schema:
        Zoi.object(%{
          requests: Zoi.map() |> Zoi.default(%{}),
          enabled: Zoi.boolean() |> Zoi.default(false),
          result: Zoi.any() |> Zoi.default(nil),
          history: Zoi.list(Zoi.string()) |> Zoi.default([]),
          settings:
            Zoi.object(%{mode: Zoi.string() |> Zoi.default("auto")})
            |> Zoi.default(%{mode: "manual"})
        })
  end

  test "generated agents retain defaults before the first request" do
    agent = DefaultAgent.new()

    assert agent.state.requests == %{}
    assert agent.state.enabled == false
    assert Map.fetch(agent.state, :result) == {:ok, nil}
    assert agent.state.history == []
    assert agent.state.settings == %{mode: "manual"}

    assert DefaultAgent.new(state: %{enabled: true}).state.enabled == true
  end

  test "missing optional fields follow Zoi default ordering" do
    schema =
      Zoi.object(%{
        skipped: Zoi.string() |> Zoi.default("skip") |> Zoi.optional(),
        included: Zoi.string() |> Zoi.optional() |> Zoi.default("keep")
      })

    assert {:ok, expected} = Zoi.parse(schema, %{})
    assert Schema.defaults_from_zoi_schema(schema) == expected
  end

  test "nested default values retain Zoi parsing semantics" do
    nested = Zoi.object(%{count: Zoi.integer() |> Zoi.default(7)}) |> Zoi.default(%{})
    schema = Zoi.object(%{nested: nested})

    assert {:ok, expected} = Zoi.parse(schema, %{})
    assert Schema.defaults_from_zoi_schema(schema) == expected
  end

  describe "merge_with_plugins/2" do
    test "nil base with no plugins returns nil" do
      assert Schema.merge_with_plugins(nil, []) == nil
    end

    test "base schema with no plugins returns base" do
      base = Zoi.object(%{mode: Zoi.atom()})
      result = Schema.merge_with_plugins(base, [])
      assert result == base
    end

    test "nil base with plugins returns plugin fields only" do
      plugin_spec = %Jido.Plugin.Spec{
        module: MyPlugin,
        name: "my_plugin",
        state_key: :my_plugin,
        schema: Zoi.object(%{count: Zoi.integer()}),
        actions: [],
        config: %{}
      }

      result = Schema.merge_with_plugins(nil, [plugin_spec])

      assert result != nil
      keys = Schema.known_keys(result)
      assert :my_plugin in keys
    end

    test "base with plugins merges both" do
      base = Zoi.object(%{mode: Zoi.atom()})

      plugin_spec = %Jido.Plugin.Spec{
        module: MyPlugin,
        name: "my_plugin",
        state_key: :plugin_data,
        schema: Zoi.object(%{value: Zoi.integer()}),
        actions: [],
        config: %{}
      }

      result = Schema.merge_with_plugins(base, [plugin_spec])

      keys = Schema.known_keys(result)
      assert :mode in keys
      assert :plugin_data in keys
    end

    test "filters out plugins without schema" do
      plugin_with_schema = %Jido.Plugin.Spec{
        module: PluginA,
        name: "plugin_a",
        state_key: :plugin_a,
        schema: Zoi.object(%{a: Zoi.integer()}),
        actions: [],
        config: %{}
      }

      plugin_without_schema = %Jido.Plugin.Spec{
        module: PluginB,
        name: "plugin_b",
        state_key: :plugin_b,
        schema: nil,
        actions: [],
        config: %{}
      }

      result = Schema.merge_with_plugins(nil, [plugin_with_schema, plugin_without_schema])

      keys = Schema.known_keys(result)
      assert :plugin_a in keys
      refute :plugin_b in keys
    end
  end

  describe "known_keys/1" do
    test "returns empty list for nil" do
      assert Schema.known_keys(nil) == []
    end

    test "returns keys from Zoi object with map fields" do
      schema = Zoi.object(%{status: Zoi.atom(), count: Zoi.integer()})
      keys = Schema.known_keys(schema)
      assert :status in keys
      assert :count in keys
    end

    test "returns keys from Zoi Map type with map fields" do
      schema = Zoi.map(%{name: Zoi.string(), age: Zoi.integer()})
      keys = Schema.known_keys(schema)
      assert :name in keys
      assert :age in keys
    end

    test "returns keys from Zoi Struct type with map fields" do
      schema =
        Zoi.struct(
          JidoTest.Agent.SchemaTest.TestStruct,
          %{field_a: Zoi.string(), field_b: Zoi.integer()}
        )

      keys = Schema.known_keys(schema)
      assert :field_a in keys
      assert :field_b in keys
    end

    test "returns empty list for unknown schema type" do
      assert Schema.known_keys("not a schema") == []
      assert Schema.known_keys(123) == []
    end
  end

  describe "defaults_from_zoi_schema/1" do
    test "returns empty map for nil" do
      assert Schema.defaults_from_zoi_schema(nil) == %{}
    end

    test "extracts defaults from Zoi object" do
      schema =
        Zoi.object(%{
          status: Zoi.atom() |> Zoi.default(:idle),
          count: Zoi.integer()
        })

      defaults = Schema.defaults_from_zoi_schema(schema)
      assert defaults == %{status: :idle}
    end

    test "handles multiple defaults" do
      schema =
        Zoi.object(%{
          status: Zoi.atom() |> Zoi.default(:idle),
          count: Zoi.integer() |> Zoi.default(0),
          name: Zoi.string()
        })

      defaults = Schema.defaults_from_zoi_schema(schema)
      assert defaults == %{status: :idle, count: 0}
    end

    test "returns empty map when no defaults" do
      schema =
        Zoi.object(%{
          status: Zoi.atom(),
          count: Zoi.integer()
        })

      defaults = Schema.defaults_from_zoi_schema(schema)
      assert defaults == %{}
    end

    test "extracts defaults from Zoi Map type" do
      schema =
        Zoi.map(%{
          name: Zoi.string() |> Zoi.default("unknown"),
          count: Zoi.integer()
        })

      defaults = Schema.defaults_from_zoi_schema(schema)
      assert defaults == %{name: "unknown"}
    end

    test "extracts defaults from Zoi Struct type" do
      schema =
        Zoi.struct(
          JidoTest.Agent.SchemaTest.TestStruct,
          %{
            field_a: Zoi.string() |> Zoi.default("default_a"),
            field_b: Zoi.integer()
          }
        )

      defaults = Schema.defaults_from_zoi_schema(schema)
      assert defaults == %{field_a: "default_a"}
    end

    test "returns empty map for unknown schema type" do
      assert Schema.defaults_from_zoi_schema("not a schema") == %{}
    end
  end
end
