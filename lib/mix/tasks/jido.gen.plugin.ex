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
    alias Jido.Igniter.Templates

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

      contents = Templates.plugin_template(inspect(module), name, state_key, signal_patterns)

      test_module_name = "JidoTest.#{module_name |> String.replace(~r/^.*?\./, "")}"
      test_module = IgniterModule.parse(test_module_name)

      test_contents = Templates.plugin_test_template(inspect(module), inspect(test_module))

      igniter
      |> IgniterModule.create_module(module, contents)
      |> IgniterModule.create_module(test_module, test_contents, location: :test)
    end
  end
end
