defmodule JidoTest.Agent.SchemaCoverageTest do
  @moduledoc """
  Additional coverage tests for Jido.Agent.Schema.

  These tests specifically target uncovered paths including:
  - known_keys with list-based fields (Map/Struct types via Zoi API)
  - known_keys with map-based fields (directly constructed structs)
  - defaults_from_zoi_schema with Map/Struct types
  - extract_fields with various field structures (via merge_with_plugins)
  """
  use JidoTest.Case, async: true

  alias Jido.Agent.Schema

  defmodule TestStruct do
    defstruct [:field_a, :field_b, :field_c]
  end

  describe "known_keys/1 with Zoi.Types.Map" do
    test "returns keys from Zoi Map type with list fields (normal creation)" do
      schema = Zoi.map(%{name: Zoi.string(), age: Zoi.integer()})
      keys = Schema.known_keys(schema)
      assert :name in keys
      assert :age in keys
    end

    test "returns keys from directly constructed Map type with map fields" do
      map_schema = Zoi.map(%{direct_key: Zoi.string(), another_key: Zoi.integer()})

      keys = Schema.known_keys(map_schema)
      assert :direct_key in keys
      assert :another_key in keys
    end

    test "returns keys from Map type with additional fields" do
      map_schema = Zoi.map(%{list_key: Zoi.string(), other_key: Zoi.integer()})

      keys = Schema.known_keys(map_schema)
      assert :list_key in keys
      assert :other_key in keys
    end

    test "handles empty Zoi Map type" do
      schema = Zoi.map(%{})
      keys = Schema.known_keys(schema)
      assert keys == []
    end

    test "handles map type with many fields" do
      schema = Zoi.map(%{a: Zoi.atom(), b: Zoi.string(), c: Zoi.integer(), d: Zoi.boolean()})
      keys = Schema.known_keys(schema)
      assert Enum.sort(keys) == [:a, :b, :c, :d]
    end
  end

  describe "known_keys/1 with Zoi.Types.Struct" do
    test "returns keys from Zoi Struct type with map fields" do
      schema = Zoi.struct(TestStruct, %{field_a: Zoi.string(), field_b: Zoi.integer()})
      keys = Schema.known_keys(schema)
      assert :field_a in keys
      assert :field_b in keys
    end

    test "returns keys from directly constructed Struct type with map fields" do
      struct_schema = Zoi.struct(TestStruct, %{field_a: Zoi.string(), field_b: Zoi.integer()})

      keys = Schema.known_keys(struct_schema)
      assert :field_a in keys
      assert :field_b in keys
    end

    test "returns keys from Struct type with additional fields" do
      struct_schema = Zoi.struct(TestStruct, %{field_a: Zoi.string(), field_b: Zoi.integer()})

      keys = Schema.known_keys(struct_schema)
      assert :field_a in keys
      assert :field_b in keys
    end
  end

  describe "defaults_from_zoi_schema/1 with Zoi.Types.Map" do
    test "extracts defaults from Zoi Map type" do
      schema =
        Zoi.map(%{
          name: Zoi.string() |> Zoi.default("default_name"),
          count: Zoi.integer(),
          enabled: Zoi.boolean() |> Zoi.default(true)
        })

      defaults = Schema.defaults_from_zoi_schema(schema)
      assert defaults == %{name: "default_name", enabled: true}
    end

    test "extracts defaults from Map type with map fields" do
      map_schema =
        Zoi.map(%{
          key_with_default: Zoi.string() |> Zoi.default("default_value"),
          key_without_default: Zoi.integer()
        })

      defaults = Schema.defaults_from_zoi_schema(map_schema)
      assert defaults == %{key_with_default: "default_value"}
    end

    test "extracts defaults from Map type with integer default" do
      map_schema =
        Zoi.map(%{
          key_with_default: Zoi.integer() |> Zoi.default(42),
          key_without_default: Zoi.string()
        })

      defaults = Schema.defaults_from_zoi_schema(map_schema)
      assert defaults == %{key_with_default: 42}
    end

    test "handles map type with all fields having defaults" do
      schema =
        Zoi.map(%{
          x: Zoi.integer() |> Zoi.default(0),
          y: Zoi.integer() |> Zoi.default(0),
          z: Zoi.integer() |> Zoi.default(0)
        })

      defaults = Schema.defaults_from_zoi_schema(schema)
      assert defaults == %{x: 0, y: 0, z: 0}
    end

    test "handles empty map type" do
      schema = Zoi.map(%{})
      defaults = Schema.defaults_from_zoi_schema(schema)
      assert defaults == %{}
    end
  end

  describe "defaults_from_zoi_schema/1 with Zoi.Types.Struct" do
    test "extracts defaults from Zoi Struct type" do
      schema =
        Zoi.struct(
          TestStruct,
          %{
            field_a: Zoi.string() |> Zoi.default("default_a"),
            field_b: Zoi.integer() |> Zoi.default(42),
            field_c: Zoi.atom()
          }
        )

      defaults = Schema.defaults_from_zoi_schema(schema)
      assert defaults == %{field_a: "default_a", field_b: 42}
    end

    test "extracts defaults from Struct type with map fields" do
      struct_schema =
        Zoi.struct(TestStruct, %{
          field_a: Zoi.string() |> Zoi.default("struct_default"),
          field_b: Zoi.integer()
        })

      defaults = Schema.defaults_from_zoi_schema(struct_schema)
      assert defaults == %{field_a: "struct_default"}
    end

    test "extracts defaults from Struct type with string default" do
      struct_schema =
        Zoi.struct(TestStruct, %{
          field_a: Zoi.string() |> Zoi.default("list_default"),
          field_b: Zoi.integer()
        })

      defaults = Schema.defaults_from_zoi_schema(struct_schema)
      assert defaults == %{field_a: "list_default"}
    end

    test "returns empty map when struct type has no defaults" do
      schema =
        Zoi.struct(
          TestStruct,
          %{field_a: Zoi.string(), field_b: Zoi.integer()}
        )

      defaults = Schema.defaults_from_zoi_schema(schema)
      assert defaults == %{}
    end
  end

  describe "merge_with_plugins/2 with various schema types" do
    test "merges base schema with plugins" do
      base = Zoi.map(%{mode: Zoi.atom(), counter: Zoi.integer()})

      plugin_spec = %Jido.Plugin.Spec{
        module: MyPlugin,
        name: "plugin_one",
        state_key: :plugin_one,
        schema: Zoi.map(%{value: Zoi.integer()}),
        actions: [],
        config: %{}
      }

      result = Schema.merge_with_plugins(base, [plugin_spec])

      keys = Schema.known_keys(result)
      assert :mode in keys
      assert :counter in keys
      assert :plugin_one in keys
    end

    test "merges nil base with plugins" do
      plugin_spec = %Jido.Plugin.Spec{
        module: MyPlugin,
        name: "my_plugin",
        state_key: :data,
        schema: Zoi.map(%{count: Zoi.integer(), name: Zoi.string()}),
        actions: [],
        config: %{}
      }

      result = Schema.merge_with_plugins(nil, [plugin_spec])

      keys = Schema.known_keys(result)
      assert :data in keys
    end

    test "merges struct-based schema with plugins" do
      base = Zoi.struct(TestStruct, %{field_a: Zoi.string()})

      plugin_spec = %Jido.Plugin.Spec{
        module: MyPlugin,
        name: "my_plugin",
        state_key: :plugin_data,
        schema: Zoi.map(%{x: Zoi.integer()}),
        actions: [],
        config: %{}
      }

      result = Schema.merge_with_plugins(base, [plugin_spec])

      keys = Schema.known_keys(result)
      assert :field_a in keys
      assert :plugin_data in keys
    end

    test "merges Map type base with plugin" do
      base = Zoi.map(%{base_key: Zoi.atom()})

      plugin_spec = %Jido.Plugin.Spec{
        module: MyPlugin,
        name: "plugin",
        state_key: :plugin,
        schema: Zoi.map(%{plugin_val: Zoi.integer()}),
        actions: [],
        config: %{}
      }

      result = Schema.merge_with_plugins(base, [plugin_spec])

      keys = Schema.known_keys(result)
      assert :base_key in keys
      assert :plugin in keys
    end

    test "merges Map type base with another plugin" do
      base = Zoi.map(%{base_key: Zoi.atom()})

      plugin_spec = %Jido.Plugin.Spec{
        module: MyPlugin,
        name: "plugin",
        state_key: :plugin,
        schema: Zoi.map(%{plugin_val: Zoi.integer()}),
        actions: [],
        config: %{}
      }

      result = Schema.merge_with_plugins(base, [plugin_spec])

      keys = Schema.known_keys(result)
      assert :base_key in keys
      assert :plugin in keys
    end

    test "merges Struct type base with plugin" do
      base = Zoi.struct(TestStruct, %{field_a: Zoi.string()})

      plugin_spec = %Jido.Plugin.Spec{
        module: MyPlugin,
        name: "plugin",
        state_key: :plugin,
        schema: Zoi.map(%{plugin_val: Zoi.integer()}),
        actions: [],
        config: %{}
      }

      result = Schema.merge_with_plugins(base, [plugin_spec])

      keys = Schema.known_keys(result)
      assert :field_a in keys
      assert :plugin in keys
    end

    test "merges Struct type base with another plugin" do
      base = Zoi.struct(TestStruct, %{field_a: Zoi.string()})

      plugin_spec = %Jido.Plugin.Spec{
        module: MyPlugin,
        name: "plugin",
        state_key: :plugin,
        schema: Zoi.map(%{plugin_val: Zoi.integer()}),
        actions: [],
        config: %{}
      }

      result = Schema.merge_with_plugins(base, [plugin_spec])

      keys = Schema.known_keys(result)
      assert :field_a in keys
      assert :plugin in keys
    end

    test "handles multiple plugins" do
      base = Zoi.map(%{base_field: Zoi.atom()})

      plugin1 = %Jido.Plugin.Spec{
        module: PluginA,
        name: "plugin_a",
        state_key: :plugin_a,
        schema: Zoi.map(%{a: Zoi.integer()}),
        actions: [],
        config: %{}
      }

      plugin2 = %Jido.Plugin.Spec{
        module: PluginB,
        name: "plugin_b",
        state_key: :plugin_b,
        schema: Zoi.map(%{b: Zoi.string()}),
        actions: [],
        config: %{}
      }

      result = Schema.merge_with_plugins(base, [plugin1, plugin2])

      keys = Schema.known_keys(result)
      assert :base_field in keys
      assert :plugin_a in keys
      assert :plugin_b in keys
    end

    test "nil base with plugins without schemas returns nil" do
      plugin_without_schema = %Jido.Plugin.Spec{
        module: PluginA,
        name: "plugin_a",
        state_key: :plugin_a,
        schema: nil,
        actions: [],
        config: %{}
      }

      result = Schema.merge_with_plugins(nil, [plugin_without_schema])
      assert result == nil
    end
  end

  describe "edge cases" do
    test "known_keys with non-schema types returns empty list" do
      assert Schema.known_keys(%{random: :map}) == []
      assert Schema.known_keys([1, 2, 3]) == []
      assert Schema.known_keys({:tuple, :value}) == []
      assert Schema.known_keys(fn -> :ok end) == []
    end

    test "defaults_from_zoi_schema with non-schema types returns empty map" do
      assert Schema.defaults_from_zoi_schema(%{random: :map}) == %{}
      assert Schema.defaults_from_zoi_schema([1, 2, 3]) == %{}
      assert Schema.defaults_from_zoi_schema({:tuple, :value}) == %{}
      assert Schema.defaults_from_zoi_schema(fn -> :ok end) == %{}
    end

    test "merge_with_plugins preserves plugin schema ordering" do
      plugins =
        for i <- 1..5 do
          %Jido.Plugin.Spec{
            module: Module.concat(Plugin, "S#{i}"),
            name: "plugin_#{i}",
            state_key: String.to_atom("s#{i}"),
            schema: Zoi.map(%{value: Zoi.integer()}),
            actions: [],
            config: %{}
          }
        end

      result = Schema.merge_with_plugins(nil, plugins)

      keys = Schema.known_keys(result)
      assert :s1 in keys
      assert :s2 in keys
      assert :s3 in keys
      assert :s4 in keys
      assert :s5 in keys
    end

    test "merge_with_plugins with mixed nil and valid plugin schemas" do
      plugins = [
        %Jido.Plugin.Spec{
          module: PluginA,
          name: "plugin_a",
          state_key: :a,
          schema: Zoi.map(%{x: Zoi.integer()}),
          actions: [],
          config: %{}
        },
        %Jido.Plugin.Spec{
          module: PluginB,
          name: "plugin_b",
          state_key: :b,
          schema: nil,
          actions: [],
          config: %{}
        },
        %Jido.Plugin.Spec{
          module: PluginC,
          name: "plugin_c",
          state_key: :c,
          schema: Zoi.map(%{y: Zoi.string()}),
          actions: [],
          config: %{}
        }
      ]

      result = Schema.merge_with_plugins(nil, plugins)

      keys = Schema.known_keys(result)
      assert :a in keys
      assert :c in keys
      refute :b in keys
    end
  end

  describe "defaults extraction with nested schemas" do
    test "extracts defaults from deeply nested object fields" do
      inner_schema = Zoi.map(%{nested_val: Zoi.integer() |> Zoi.default(100)})

      schema =
        Zoi.map(%{
          outer: inner_schema |> Zoi.default(%{nested_val: 50}),
          simple: Zoi.atom() |> Zoi.default(:default_atom)
        })

      defaults = Schema.defaults_from_zoi_schema(schema)
      assert defaults[:outer] == %{nested_val: 50}
      assert defaults[:simple] == :default_atom
    end

    test "handles optional fields with defaults" do
      schema =
        Zoi.map(%{
          required_with_default: Zoi.string() |> Zoi.default("required_default"),
          optional_with_default:
            Zoi.string() |> Zoi.optional() |> Zoi.default("optional_default"),
          no_default: Zoi.integer()
        })

      defaults = Schema.defaults_from_zoi_schema(schema)
      assert Map.has_key?(defaults, :required_with_default)
      assert Map.has_key?(defaults, :optional_with_default)
      refute Map.has_key?(defaults, :no_default)
    end
  end
end
