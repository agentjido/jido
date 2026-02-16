if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Jido.Gen.Sensor do
    @shortdoc "Generates a Jido Sensor module"

    @moduledoc """
    Generates a Jido Sensor module.

        $ mix jido.gen.sensor MyApp.Sensors.Temperature

    ## Options

    - `--interval` - Polling interval in milliseconds (default: 5000)

    ## Examples

        $ mix jido.gen.sensor MyApp.Sensors.Temperature
        $ mix jido.gen.sensor MyApp.Sensors.Metrics --interval=10000
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
          interval: :integer
        ],
        defaults: [
          interval: 5000
        ],
        example: "mix jido.gen.sensor MyApp.Sensors.Temperature"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      options = igniter.args.options
      positional = igniter.args.positional

      module_name = positional[:module]
      module = IgniterModule.parse(module_name)
      name = Helpers.module_to_name(module_name)
      interval = options[:interval]

      contents = Templates.sensor_template(inspect(module), name, interval)

      test_module_name = "JidoTest.#{module_name |> String.replace(~r/^.*?\./, "")}"
      test_module = IgniterModule.parse(test_module_name)

      test_contents = Templates.sensor_test_template(inspect(module), inspect(test_module))

      igniter
      |> IgniterModule.create_module(module, contents)
      |> IgniterModule.create_module(test_module, test_contents, location: :test)
    end
  end
end
