if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Jido.Gen.Plugin do
    @shortdoc "Generates a Jido Plugin module"

    @moduledoc """
    Generates a Jido Plugin module.

        $ mix jido.gen.plugin MyApp.Plugins.Chat

    ## Options

    - `--signals` - Comma-separated list of signal patterns (default: none)

    ## Examples

        $ mix jido.gen.plugin MyApp.Plugins.Chat
        $ mix jido.gen.plugin MyApp.Plugins.Chat --signals="chat.*,message.*"
    """

    use Igniter.Mix.Task

    alias Igniter.Project.Module, as: IgniterModule
    alias Jido.Igniter.Helpers

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :jido,
        positional: [:module],
        schema: [
          signals: :string
        ],
        defaults: [
          signals: nil
        ],
        example: "mix jido.gen.plugin MyApp.Plugins.Chat"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      options = igniter.args.options
      positional = igniter.args.positional

      module_name = positional[:module]
      module = IgniterModule.parse(module_name)
      name = Helpers.module_to_name(module_name)
      state_key = name

      signal_patterns = Helpers.parse_list(options[:signals])

      patterns_str = Enum.map_join(signal_patterns, ", ", &~s("#{&1}"))

      contents = """
      defmodule #{inspect(module)} do
        use Jido.Plugin,
          name: "#{name}",
          state_key: :#{state_key},
          actions: [],
          schema: Zoi.object(%{}),
          signal_patterns: [#{patterns_str}]

        @impl Jido.Plugin
        def signal_routes(_config) do
          []
        end
      end
      """

      test_module_name = "JidoTest.#{module_name |> String.replace(~r/^.*?\./, "")}"
      test_module = IgniterModule.parse(test_module_name)

      plugin_alias = module |> Module.split() |> List.last()

      test_contents = """
      defmodule #{inspect(test_module)} do
        use ExUnit.Case, async: true

        alias #{inspect(module)}

        describe "plugin_spec/1" do
          test "returns plugin specification" do
            spec = #{plugin_alias}.plugin_spec(%{})
            assert spec.module == #{plugin_alias}
            assert spec.name == #{plugin_alias}.name()
          end
        end

        describe "mount/2" do
          test "returns default state" do
            assert {:ok, %{}} = #{plugin_alias}.mount(nil, %{})
          end
        end
      end
      """

      igniter
      |> IgniterModule.create_module(module, contents)
      |> IgniterModule.create_module(test_module, test_contents, location: :test)
    end
  end
end
