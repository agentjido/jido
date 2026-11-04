defmodule JidoActionTest.Authoring.FlowEdges.Record do
  use Jido.Action, name: "authoring_record"

  @impl true
  def run(%{label: label, value: value}, %{observer: observer, run_ref: ref}) do
    send(observer, {ref, label})
    {:ok, %{value: value}}
  end
end

defmodule JidoActionTest.Authoring.FlowEdges.Join do
  use Jido.Action, name: "authoring_join"

  @impl true
  def run(%{left: left, right: right} = params, %{observer: observer, run_ref: ref}) do
    send(observer, {ref, :join})
    {:ok, %{total: left + right, input_keys: Map.keys(params) |> Enum.sort()}}
  end
end

defmodule JidoActionTest.Authoring.FlowEdges.Dependencies do
  use Jido.Flow, name: "authoring_dependencies"

  flow do
    step "join",
      action: JidoActionTest.Authoring.FlowEdges.Join,
      params: %{
        left: result("left", :value),
        right: result("right", :value)
      },
      needs: ["audit"]

    step "right",
      action: JidoActionTest.Authoring.FlowEdges.Record,
      params: %{label: :right, value: input(:right)}

    step "audit",
      action: JidoActionTest.Authoring.FlowEdges.Record,
      params: %{label: :audit, value: input(:audit)}

    step "left",
      action: JidoActionTest.Authoring.FlowEdges.Record,
      params: %{label: :left, value: input(:left)}

    output result("join")
  end
end

defmodule JidoActionTest.Authoring.FlowEdges.Route do
  use Jido.Action, name: "authoring_route"

  @impl true
  def run(%{route: route} = params, %{observer: observer, run_ref: ref}) do
    send(observer, {ref, route})
    {:ok, params}
  end
end

defmodule JidoActionTest.Authoring.FlowEdges.FailRoute do
  use Jido.Action, name: "authoring_fail_route"

  @impl true
  def run(_params, %{observer: observer, run_ref: ref}) do
    send(observer, {ref, :failed_route})
    {:error, Jido.Error.execution_error("selected route failed")}
  end
end

defmodule JidoActionTest.Authoring.FlowEdges.Routing do
  use Jido.Flow, name: "authoring_routing"

  alias JidoActionTest.Authoring.FlowEdges.Route, as: R

  flow do
    step "unused_route_data",
      action: JidoActionTest.Authoring.FlowEdges.Record,
      params: %{label: :unused_route_data, value: input(:value)}

    choice "route" do
      option "urgent",
        condition: input(:score) >= 90,
        action: JidoActionTest.Authoring.FlowEdges.Route,
        params: %{route: :urgent, value: input(:value)}

      option "priority",
        condition: input(:score) >= 50,
        action: JidoActionTest.Authoring.FlowEdges.Route,
        params: %{route: :priority, value: input(:value)}

      option "failed",
        condition: input(:fail) == true,
        action: JidoActionTest.Authoring.FlowEdges.FailRoute,
        params: %{}

      otherwise action: R, params: %{route: :standard, value: result("unused_route_data", :value)}
    end

    output result("route")
  end
end

defmodule JidoActionTest.Authoring.FlowEdges.ChildWork do
  use Jido.Action, name: "authoring_child_work"

  @impl true
  def run(%{value: value}, _context) when value < 0,
    do: {:error, Jido.Error.execution_error("negative value")}

  def run(%{value: value}, _context), do: {:ok, %{value: value + 1}}
end

defmodule JidoActionTest.Authoring.FlowEdges.Child do
  use Jido.Flow,
    name: "authoring_child",
    schema: Jido.Joi.object(%{value: Jido.Joi.integer()}),
    output_schema: Jido.Joi.object(%{value: Jido.Joi.integer(), label: Jido.Joi.string()})

  flow do
    step "compute",
      action: JidoActionTest.Authoring.FlowEdges.ChildWork,
      params: %{value: input(:value)}

    output %{value: result("compute", :value), label: context(:label)}
  end
end

defmodule JidoActionTest.Authoring.FlowEdges.Parent do
  use Jido.Flow,
    name: "authoring_parent",
    schema: Jido.Joi.object(%{value: Jido.Joi.any()})

  flow do
    step "child",
      action: JidoActionTest.Authoring.FlowEdges.Child,
      params: %{value: input(:value)}

    output %{child: result("child")}
  end
end
