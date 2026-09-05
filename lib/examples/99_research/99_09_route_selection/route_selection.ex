defmodule Jido.Examples.RouteSelection.Record do
  @moduledoc false
  use Jido.Action, name: "research_route_record"

  def run(%{handler: handler}, %{agent_state: state}) do
    {:ok, %{state | handler: handler}}
  end
end

defmodule Jido.Examples.RouteSelection.Rewrite do
  @moduledoc "Prepares a different Signal type to test the route selection boundary."
  use Jido.Plugin

  def prepare(command, _opts) do
    {:ok, %{command | signal: %{command.signal | type: "order.cancel"}}}
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

defmodule Jido.Examples.RouteSelection.Rewritten do
  @moduledoc "A Plugin changes the Signal type before route selection."
  use Jido.Agent, name: "research_route_rewritten"
  alias Jido.Examples.RouteSelection.{Record, Rewrite}

  agent do
    schema Zoi.object(%{handler: Zoi.string() |> Zoi.default("")})
    plugin Rewrite
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
  alias __MODULE__.{Fallback, Rewritten, Single}

  def new(mode) do
    module =
      case mode do
        :fallback -> Fallback
        :rewrite -> Rewritten
        :single -> Single
      end

    module.new!(id: "order-router")
  end

  def signal(type), do: Jido.Signal.new!(type, %{}, source: "/examples/route-selection")
end
