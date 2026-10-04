defmodule Jido.Examples.DataDefinedAgent do
  @moduledoc "Builds, encodes, and runs one neutral Agent definition."

  alias Jido.Agent
  alias Jido.Agent.Codec
  alias Jido.Codec.Registry

  defmodule Add do
    @moduledoc "Adds one validated amount to the current count."
    use Jido.Action,
      name: "basic_data_defined_add",
      schema: Zoi.object(%{amount: Zoi.integer()})

    def run(%{amount: amount}, %{agent_state: state}),
      do: {:ok, %{state | count: state.count + amount}}
  end

  defmodule CountTurns do
    @moduledoc "Owns a count of committed Turns."
    use Jido.Plugin

    @impl true
    def state_spec(_opts), do: {:turns, Zoi.integer() |> Zoi.min(0) |> Zoi.default(0)}

    @impl true
    def reduce(reduction, _opts), do: {:ok, reduction.plugin_state + 1}
  end

  @doc "Returns the validated neutral Agent definition."
  def definition do
    Agent.new!(
      name: "basic_data_defined_agent",
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
      plugins: [CountTurns],
      routes: [{"examples.basic.data_defined.add", Add}]
    )
  end

  @doc "Returns the stable allowlist used to encode and decode the definition."
  def registry(definition \\ definition()) do
    Registry.new!(%{
      "agents/neutral" => {:agent, Agent},
      "actions/add" => {:action, Add},
      "plugins/count-turns" => {:plugin, CountTurns},
      "schemas/count" => {:schema, definition.schema}
    })
  end

  @doc "Encodes the static definition with stable Registry identifiers."
  def encode do
    definition = definition()
    registry = registry(definition)
    {:ok, document} = Codec.encode(definition, registry)
    {document, registry}
  end

  @doc "Builds one command Signal for the data-defined route."
  def signal!(amount) do
    Jido.Signal.new!(
      "examples.basic.data_defined.add",
      %{amount: amount},
      source: "/examples/basic/data_defined_agent"
    )
  end
end
