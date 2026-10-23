defmodule Jido.Examples.RouteSelection do
  @moduledoc "Shows route declaration order with exact, wildcard, and fallback routes."

  defmodule Record do
    @moduledoc "Stores the selected handler name."
    use Jido.Action,
      name: "basic_route_selection_record",
      schema: Zoi.object(%{handler: Zoi.string()}),
      output_schema: Zoi.map()

    def run(%{handler: handler}, %{agent_state: state}),
      do: {:ok, %{state | handler: handler}}
  end

  use Jido.Agent, name: "basic_route_selection"

  alias __MODULE__.Record

  state do
    schema Zoi.object(%{handler: Zoi.string() |> Zoi.default("")})
  end

  routes do
    signal_source "/examples/basic/route_selection"

    # The first matching route wins. Keep the fallback last.
    route "examples.basic.route_selection.order.create", Record,
      as: :create,
      defaults: %{handler: "create"} do
      state(from: output())
    end

    route "examples.basic.route_selection.order.*", Record, defaults: %{handler: "order"} do
      state(from: output())
    end

    route "**", Record, defaults: %{handler: "fallback"} do
      state(from: output())
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
  @moduledoc "Has no fallback route, so unmatched input returns an unmatched_input error."
  use Jido.Agent, name: "basic_strict_route_selection"

  state do
    schema Zoi.object(%{handled: Zoi.boolean() |> Zoi.default(false)})
  end

  routes do
    signal_source "/examples/basic/route_selection"

    route "examples.basic.route_selection.order.create" do
      action _input, schema: Zoi.object(%{}), context: context, output_schema: Zoi.map() do
        {:ok, %{context.agent_state | handled: true}}
      end

      state(from: output())
    end
  end
end
