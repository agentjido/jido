defmodule Jido.Examples.ConditionalRoutes.Select do
  @moduledoc false
  use Jido.Action, name: "workflow_route_select"

  def run(input, context) do
    Jido.Examples.Workflow.Observation.record(context, input.route, input)

    case input.route do
      :reject ->
        {:error, Jido.Action.Error.execution_error("primary rejected", stage: :reject)}

      :fallback ->
        {module, client} = context.service

        case module.call(client, :fallback, %{}) do
          {:ok, value} ->
            {:ok, %{route: :fallback, result: value}}

          {:error, reason} ->
            {:error, Jido.Action.Error.execution_error("fallback failed", reason: reason)}
        end

      route ->
        if context[:reject_selected],
          do: {:error, Jido.Action.Error.execution_error("selected route failed", stage: route)},
          else: {:ok, %{route: route, result: input.value}}
    end
  end
end

defmodule Jido.Examples.ConditionalRoutes.Pipeline do
  @moduledoc "The first matching Choice runs; expected failure capture is explicit."
  use Jido.Flow, name: "workflow_routes"

  flow do
    step "fetch", [params <- input(), ctx <- context()] do
      {module, client} = ctx.service

      case module.call(client, :primary, params) do
        {:ok, value} -> {:ok, %{status: :ok, value: value, reason: nil}}
        {:error, reason} -> {:ok, %{status: :error, value: %{}, reason: reason}}
      end
    end

    choice "route" do
      option "primary",
        condition: result("fetch", :status) == :ok,
        action: Jido.Examples.ConditionalRoutes.Select,
        params: %{route: :primary, value: result("fetch", :value)}

      option "also_matches",
        condition: result("fetch", :status) == :ok,
        action: Jido.Examples.ConditionalRoutes.Select,
        params: %{route: :second, value: result("fetch", :value)}

      option "fallback",
        condition: result("fetch", :reason) == :unavailable,
        action: Jido.Examples.ConditionalRoutes.Select,
        params: %{route: :fallback}

      otherwise action: Jido.Examples.ConditionalRoutes.Select, params: %{route: :reject}
    end

    output result("route")
  end
end

defmodule Jido.Examples.ConditionalRoutes do
  @moduledoc "Explicit provider policy composed with ordered SDK Choice execution."
  use Jido.Agent, name: "workflow_routes_agent"

  agent do
    schema Zoi.object(%{
             route: Zoi.atom() |> Zoi.default(:none),
             result: Zoi.map() |> Zoi.default(%{})
           })
  end

  routes do
    signal_source "/workflow"

    route "workflow.routes", Jido.Examples.ConditionalRoutes.Pipeline do
      define :fetch
    end
  end
end
