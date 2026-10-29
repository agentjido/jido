defmodule Jido.Agent.OptionsTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Options

  defmodule RequiredPlugin do
    use Jido.Plugin, id: "test.agent.options.required"
  end

  defmodule OptionalPlugin do
    use Jido.Plugin, id: "test.agent.options.optional"
  end

  test "prepares public options with the same default Agent ID" do
    options = Options.prepare!(quote(do: [name: "prepared"]), __ENV__)

    assert options[:name] == "prepared"
    assert options[:id] == Atom.to_string(__MODULE__)
    refute Keyword.has_key?(options, :plugin_providers)
    refute Keyword.has_key?(options, :plugin_declarations)
  end

  test "keeps an explicit ID and public Plugin declarations" do
    options =
      Options.prepare!(
        quote(do: [name: "prepared", id: "test/prepared", plugins: [OptionalPlugin]]),
        __ENV__
      )

    assert options[:id] == "test/prepared"
    assert options[:plugins] == [OptionalPlugin]
  end

  test "rejects malformed, repeated, and invalid identity options" do
    for quoted <- [quote(do: :invalid), quote(do: [name: "first", name: "second"])] do
      assert_raise ArgumentError, ~r/unique keyword options/, fn ->
        Options.prepare!(quoted, __ENV__)
      end
    end

    assert_raise Jido.Authoring.Registry.Error, ~r/Registry identifier/, fn ->
      Options.prepare!(quote(do: [name: "invalid", id: "bad id"]), __ENV__)
    end
  end

  test "prepends one required Plugin and keeps the public option last" do
    options = [name: "prepared", plugins: [OptionalPlugin]]

    assert [name: "prepared", plugins: [RequiredPlugin, OptionalPlugin]] =
             Options.prepend_plugin(options, RequiredPlugin)

    assert [name: "prepared", plugins: [RequiredPlugin]] =
             Options.prepend_plugin(
               [name: "prepared", plugins: [RequiredPlugin]],
               RequiredPlugin
             )
  end

  test "leaves caller conflicts for normal Agent validation" do
    configured = {RequiredPlugin, %{mode: :strict}}

    assert [plugins: [RequiredPlugin, ^configured]] =
             Options.prepend_plugin([plugins: [configured]], RequiredPlugin)

    assert [plugins: [RequiredPlugin, RequiredPlugin]] =
             Options.prepend_plugin(
               [plugins: [RequiredPlugin, RequiredPlugin]],
               RequiredPlugin
             )

    assert_raise ArgumentError, ~r/plugins must be a list/, fn ->
      Options.prepend_plugin([plugins: RequiredPlugin], RequiredPlugin)
    end
  end
end
