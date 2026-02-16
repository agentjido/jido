if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Jido.Gen.Agent do
    @shortdoc "Generates a Jido Agent module"

    @moduledoc """
    Generates a Jido Agent module.

        $ mix jido.gen.agent MyApp.Agents.Coordinator

    ## Options

    - `--plugins` - Comma-separated list of plugin modules to attach (default: none)

    ## Examples

        $ mix jido.gen.agent MyApp.Agents.Coordinator
        $ mix jido.gen.agent MyApp.Agents.Chat --plugins=MyApp.Plugins.Chat
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
          plugins: :string
        ],
        defaults: [
          plugins: nil
        ],
        example: "mix jido.gen.agent MyApp.Agents.Coordinator"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      options = igniter.args.options
      positional = igniter.args.positional

      module_name = positional[:module]
      module = IgniterModule.parse(module_name)
      name = Helpers.module_to_name(module_name)

      plugins =
        options[:plugins]
        |> Helpers.parse_list()
        |> Enum.map(&String.to_atom/1)

      contents = Templates.agent_template(inspect(module), name, plugins: plugins)

      test_module_name = "JidoTest.#{module_name |> String.replace(~r/^.*?\./, "")}"
      test_module = IgniterModule.parse(test_module_name)

      test_contents = Templates.agent_test_template(inspect(module), inspect(test_module))

      igniter
      |> IgniterModule.create_module(module, contents)
      |> IgniterModule.create_module(test_module, test_contents, location: :test)
    end
  end
end
