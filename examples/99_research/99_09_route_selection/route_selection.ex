defmodule Jido.Examples.RouteSelection.Record do
  @moduledoc false
  use Jido.Action, name: "research_route_record"

  def run(%{handler: handler}, %{agent_state: state}) do
    {:ok, %{state | handler: handler}}
  end
end

defmodule Jido.Examples.RouteSelection.Single do
  @moduledoc "A single route provides the control."
  use Jido.Agent, name: "research_route_single"
  alias Jido.Examples.RouteSelection.Record

  agent do
    schema Zoi.object(%{handler: Zoi.string() |> Zoi.default("")})
  end

  routes do
    signal_source "/examples/route-selection"

    route "order.create", Record do
      defaults %{handler: "create"}
    end
  end
end

defmodule Jido.Examples.RouteSelection.Fallback do
  @moduledoc "An exact route competes with two wildcard routes."
  use Jido.Agent, name: "research_route_fallback"
  alias Jido.Examples.RouteSelection.Record

  agent do
    schema Zoi.object(%{handler: Zoi.string() |> Zoi.default("")})
  end

  routes do
    signal_source "/examples/route-selection"

    route "order.create", Record do
      defaults %{handler: "create"}
    end

    route "order.*", Record do
      defaults %{handler: "order"}
    end

    route "**", Record do
      defaults %{handler: "fallback"}
    end
  end
end

defmodule Jido.Examples.RouteSelection.Fixed do
  @moduledoc "A two-route Agent keeps selection in the Agent boundary."
  use Jido.Agent, name: "research_route_fixed"
  alias Jido.Examples.RouteSelection.Record

  agent do
    schema Zoi.object(%{handler: Zoi.string() |> Zoi.default("")})
  end

  routes do
    signal_source "/examples/route-selection"

    route "order.create", Record do
      defaults %{handler: "create"}
    end

    route "order.cancel", Record do
      defaults %{handler: "cancel"}
    end
  end
end

defmodule Jido.Examples.RouteSelection do
  @moduledoc "Route precedence and fixed selection with explicit DSL definitions."
  alias __MODULE__.{Fallback, Fixed, Single}

  def new(mode) do
    module =
      case mode do
        :fallback -> Fallback
        :fixed -> Fixed
        :single -> Single
      end

    module.new!(id: "order-router")
  end

  def signal(type), do: Jido.Signal.new!(type, %{}, source: "/examples/route-selection")
end
