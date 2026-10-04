defmodule Jido.Examples.RouteSelection do
  @moduledoc "Shows exact, wildcard, and fallback route selection."

  defmodule Record do
    @moduledoc "Stores the selected handler name."
    use Jido.Action,
      name: "basic_route_selection_record",
      schema: Zoi.object(%{handler: Zoi.string()})

    def run(%{handler: handler}, %{agent_state: state}),
      do: {:ok, %{state | handler: handler}}
  end

  use Jido.Agent, name: "basic_route_selection"

  alias __MODULE__.Record

  agent do
    schema Zoi.object(%{handler: Zoi.string() |> Zoi.default("")})
  end

  routes do
    signal_source "/examples/basic/route_selection"

    route "**", Record do
      defaults %{handler: "fallback"}
    end

    route "examples.basic.route_selection.order.*", Record do
      defaults %{handler: "order"}
      priority 100
    end

    route "examples.basic.route_selection.order.create", Record, as: :create do
      defaults %{handler: "create"}
      priority -100
    end

    route "examples.basic.route_selection.order.priority", Record do
      defaults %{handler: "low-priority"}
      priority -10
    end

    route "examples.basic.route_selection.order.priority", Record do
      defaults %{handler: "high-priority"}
      priority 10
    end
  end

  @doc "Builds one command Signal for this router."
  def signal!(suffix) when is_binary(suffix) do
    Jido.Signal.new!(
      "examples.basic.route_selection.#{suffix}",
      %{},
      source: "/examples/basic/route_selection"
    )
  end
end

defmodule Jido.Examples.RouteSelection.Strict do
  @moduledoc "Has no fallback route, so unmatched input returns a routing error."
  use Jido.Agent, name: "basic_strict_route_selection"

  agent do
    schema Zoi.object(%{handled: Zoi.boolean() |> Zoi.default(false)})
  end

  routes do
    signal_source "/examples/basic/route_selection"

    route "examples.basic.route_selection.order.create" do
      action _input, schema: Zoi.object(%{}), context: context do
        {:ok, %{context.agent_state | handled: true}}
      end
    end
  end
end
