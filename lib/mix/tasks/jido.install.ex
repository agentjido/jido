if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Jido.Install do
    @shortdoc "Installs Jido in your project"

    @moduledoc """
    Installs and configures Jido in your project.

        $ mix jido.install

    This task will:

    1. Add Jido configuration to `config/config.exs`
    2. Create a `<YourApp>.Jido` instance module
    3. Optionally add `<YourApp>.Jido` to your application's supervision tree
    4. Optionally generate an example agent

    ## Options

    - `--no-supervisor` - Skip adding Jido instance to the supervision tree
    - `--example` - Generate an example agent module

    ## Examples

        $ mix jido.install
        $ mix jido.install --example
        $ mix jido.install --no-supervisor
    """

    use Igniter.Mix.Task

    alias Igniter.Project.Application
    alias Igniter.Project.Config
    alias Igniter.Project.Module, as: IgniterModule

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :jido,
        adds_deps: [],
        installs: [],
        schema: [
          no_supervisor: :boolean,
          example: :boolean
        ],
        defaults: [
          no_supervisor: false,
          example: false
        ],
        example: "mix jido.install"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      options = igniter.args.options
      app_name = Application.app_name(igniter)
      jido_module = Module.concat([Macro.camelize(to_string(app_name)), "Jido"])
      jido_module_contents = "use Jido, otp_app: #{inspect(app_name)}"

      igniter =
        igniter
        |> IgniterModule.find_and_update_or_create_module(
          jido_module,
          jido_module_contents,
          fn zipper -> {:ok, zipper} end
        )
        |> Config.configure_new(
          "config.exs",
          app_name,
          [jido_module],
          max_tasks: 1000,
          agent_pools: []
        )

      igniter =
        if options[:no_supervisor] do
          igniter
        else
          Application.add_new_child(
            igniter,
            jido_module,
            after: [Ecto.Repo, Phoenix.PubSub]
          )
        end

      igniter =
        if options[:example] do
          example_module =
            Module.concat([Macro.camelize(to_string(app_name)), "Agents", "Example"])

          Igniter.compose_task(igniter, "jido.gen.agent", [inspect(example_module)])
        else
          igniter
        end

      igniter
    end
  end
else
  defmodule Mix.Tasks.Jido.Install do
    @moduledoc "Installs Jido. Should be run with `mix igniter.install jido`"
    @shortdoc @moduledoc

    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task 'jido.install' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
