defmodule Jido.Examples.DataDefinedAgent do
  @moduledoc "Builds, encodes, and runs one neutral Agent definition."

  alias Jido.Agent
  alias Jido.Agent.Codec

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
    Agent.define!(%{
      name: "basic_data_defined_agent",
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
      extensions: [%{id: CountTurns.id(), provider: CountTurns, vsn: 1, data: %{}}],
      routes: [%{path: "examples.basic.data_defined.add", handler: %{kind: :action, target: Add}}]
    })
  end

  @doc "Encodes one validated definition with a trusted reference Registry."
  def encode do
    {:ok, document, registry} = Codec.encode(definition())
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
