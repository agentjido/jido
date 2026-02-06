defmodule JidoTest.Plugin.SingletonCompileTest do
  use ExUnit.Case, async: true

  defmodule SingletonFixture do
    @moduledoc false
    use Jido.Plugin,
      name: "singleton_fixture",
      state_key: :singleton_fix,
      actions: [JidoTest.PluginTestAction],
      singleton: true
  end

  defmodule RegularFixture do
    @moduledoc false
    use Jido.Plugin,
      name: "regular_fixture",
      state_key: :regular_fix,
      actions: [JidoTest.PluginTestAction]
  end

  describe "compile-time singleton enforcement" do
    test "agent with singleton plugin compiles successfully" do
      defmodule ValidSingletonAgent do
        use Jido.Agent,
          name: "valid_singleton",
          default_plugins: false,
          plugins: [SingletonFixture]
      end

      assert ValidSingletonAgent.plugins() |> length() == 1
    end

    test "agent with singleton and regular plugins compiles" do
      defmodule MixedPluginAgent do
        use Jido.Agent,
          name: "mixed_plugins",
          default_plugins: false,
          plugins: [SingletonFixture, RegularFixture]
      end

      assert MixedPluginAgent.plugins() |> length() == 2
    end

    test "agent raises when singleton plugin is aliased" do
      assert_raise ArgumentError, ~r/Cannot alias singleton plugin/, fn ->
        defmodule AliasedSingletonAgent do
          use Jido.Agent,
            name: "aliased_singleton",
            plugins: [{SingletonFixture, as: :custom}]
        end
      end
    end

    test "agent raises CompileError when singleton plugin is duplicated" do
      assert_raise CompileError, ~r/Duplicate singleton plugins/, fn ->
        defmodule DuplicateSingletonAgent do
          use Jido.Agent,
            name: "duplicate_singleton",
            plugins: [SingletonFixture, SingletonFixture]
        end
      end
    end

    test "regular (non-singleton) plugin can still be aliased" do
      defmodule AliasedRegularAgent do
        use Jido.Agent,
          name: "aliased_regular",
          default_plugins: false,
          plugins: [{RegularFixture, as: :alias1}]
      end

      instances = AliasedRegularAgent.plugin_instances()
      assert length(instances) == 1
      assert hd(instances).as == :alias1
    end
  end
end
