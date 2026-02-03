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

      plugins_opt =
        if Enum.empty?(plugins) do
          ""
        else
          plugins_str = Enum.map_join(plugins, ", ", &inspect/1)
          ",\n    plugins: [#{plugins_str}]"
        end

      contents = """
      defmodule #{inspect(module)} do
        use Jido.Agent,
          name: "#{name}",
          description: "TODO: Add description",
          schema: []#{plugins_opt}
      end
      """

      test_module_name = "JidoTest.#{module_name |> String.replace(~r/^.*?\./, "")}"
      test_module = IgniterModule.parse(test_module_name)

      agent_alias = module |> Module.split() |> List.last()

      test_contents = """
      defmodule #{inspect(test_module)} do
        use ExUnit.Case, async: true

        alias #{inspect(module)}

        describe "new/1" do
          test "creates agent with default state" do
            agent = #{agent_alias}.new()
            assert agent.name == #{agent_alias}.name()
          end

          test "creates agent with custom id" do
            agent = #{agent_alias}.new(id: "custom-id")
            assert agent.id == "custom-id"
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
