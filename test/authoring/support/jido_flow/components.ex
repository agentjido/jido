defmodule Jido.Test.Flow.Authoring.Components.MapItem do
  use Jido.Action, name: "authoring_map_item"

  @impl true
  def run(%{value: value, index: index, item_id: item_id}, context) do
    if observer = context[:observer], do: send(observer, {:map_item, value})

    if value == :bad do
      {:error, Jido.Error.execution_error("bad map item")}
    else
      {:ok, %{value: value * 2, index: index, item_id: item_id}}
    end
  end
end

defmodule Jido.Test.Flow.Authoring.Components.GatedMapItem do
  use Jido.Action, name: "authoring_gated_map_item"

  @impl true
  def run(%{value: value, index: index, item_id: item_id}, %{observer: observer}) do
    send(observer, {:map_started, index, value, item_id, self()})

    receive do
      {:release_map_item, ^index} -> {:ok, %{value: value, index: index, item_id: item_id}}
    end
  end
end

defmodule Jido.Test.Flow.Authoring.Components.Fold do
  use Jido.Action, name: "authoring_fold"

  @impl true
  def run(%{acc: acc, item: item}, context) do
    if observer = context[:observer], do: send(observer, {:fold, item, acc})

    if item == :bad,
      do: {:error, Jido.Error.execution_error("bad fold item")},
      else: {:ok, %{value: acc * 10 - item}}
  end
end

defmodule Jido.Test.Flow.Authoring.Components.Advance do
  use Jido.Action, name: "authoring_advance"

  @impl true
  def run(%{count: count, index: index, previous: previous}, context) do
    if observer = context[:observer], do: send(observer, {:iteration, count, index, previous})

    if context[:fail_at] == count do
      {:error, Jido.Error.execution_error("bad iteration")}
    else
      {:ok, %{count: count + 1, index: index}}
    end
  end
end

defmodule Jido.Test.Flow.Authoring.Components.Echo do
  use Jido.Action, name: "authoring_component_echo"

  @impl true
  def run(params, _context), do: {:ok, params}
end

defmodule Jido.Test.Flow.Authoring.Components.Decide do
  use Jido.Action, name: "authoring_decide"

  @impl true
  def run(params, _context), do: {:ok, params}
end

defmodule Jido.Test.Flow.Authoring.Components.Expand do
  use Jido.Action, name: "authoring_expand"

  @impl true
  def run(%{mode: :finish, value: value}, context),
    do: {:ok, %{value: value, label: context.label}}

  def run(%{mode: :continue, value: value, target: target}, _context),
    do: {:continue, %{value: value}, target}
end

defmodule Jido.Test.Flow.Authoring.Components.Final do
  use Jido.Action, name: "authoring_final"

  @impl true
  def run(%{value: value}, context), do: {:ok, %{value: value + 1, label: context.label}}
end

defmodule Jido.Test.Flow.Authoring.Components.MapKeyword do
  use Jido.Flow, name: "authoring_map"

  flow do
    map "items",
      collection: input(:items),
      action: Jido.Test.Flow.Authoring.Components.MapItem,
      params: %{value: item(), index: item_index(), item_id: item_id()}

    output %{items: result("items")}
  end
end

defmodule Jido.Test.Flow.Authoring.Components.MapBlock do
  use Jido.Flow, name: "authoring_map"

  flow do
    map "items" do
      collection input(:items)
      action Jido.Test.Flow.Authoring.Components.MapItem
      params %{value: item(), index: item_index(), item_id: item_id()}
    end

    output %{items: result("items")}
  end
end

defmodule Jido.Test.Flow.Authoring.Components.MapCollect do
  use Jido.Flow, name: "authoring_map_collect"

  flow do
    map "items",
      collection: input(:items),
      action: Jido.Test.Flow.Authoring.Components.MapItem,
      params: %{value: item(), index: item_index(), item_id: item_id()},
      on_error: :collect_errors

    output %{items: result("items")}
  end
end

defmodule Jido.Test.Flow.Authoring.Components.GatedMapFlow do
  use Jido.Flow, name: "authoring_gated_map"

  flow do
    map "items",
      collection: input(:items),
      action: Jido.Test.Flow.Authoring.Components.GatedMapItem,
      params: %{value: item(), index: item_index(), item_id: item_id()}

    output %{items: result("items")}
  end
end

defmodule Jido.Test.Flow.Authoring.Components.ReduceFlow do
  use Jido.Flow, name: "authoring_reduce"

  flow do
    reduce "fold" do
      collection input(:items)
      initial %{value: 1}
      action Jido.Test.Flow.Authoring.Components.Fold
      params %{acc: accumulator(:value), item: item()}
    end

    output result("fold")
  end
end

defmodule Jido.Test.Flow.Authoring.Components.IterateRepeat do
  use Jido.Flow, name: "authoring_iterate_repeat"

  flow do
    iterate "counter" do
      state Jido.Joi.object(%{count: Jido.Joi.integer()}), initial: %{count: 0}
      action Jido.Test.Flow.Authoring.Components.Advance
      params %{count: state(:count), index: iteration_index(), previous: body_result()}
      update %{count: body_result(:count)}
      repeat 3
    end

    output %{counter: result("counter")}
  end
end

defmodule Jido.Test.Flow.Authoring.Components.IterateWhile do
  use Jido.Flow, name: "authoring_iterate_while"

  flow do
    iterate "counter" do
      state Jido.Joi.object(%{count: Jido.Joi.integer()}), initial: %{count: 0}
      action Jido.Test.Flow.Authoring.Components.Advance
      params %{count: state(:count), index: iteration_index(), previous: body_result()}
      update %{count: body_result(:count)}
      while state(:count) < input(:limit)
      max_iterations 4
    end

    output %{counter: result("counter")}
  end
end

defmodule Jido.Test.Flow.Authoring.Components.Child do
  use Jido.Flow,
    name: "authoring_component_child",
    schema: Jido.Joi.object(%{value: Jido.Joi.integer()}),
    output_schema: Jido.Joi.object(%{value: Jido.Joi.integer(), label: Jido.Joi.string()})

  flow do
    step "echo",
      action: Jido.Test.Flow.Authoring.Components.Echo,
      params: %{value: input(:value)}

    output %{value: result("echo", :value), label: context(:label)}
  end
end

defmodule Jido.Test.Flow.Authoring.Components.Parent do
  use Jido.Flow, name: "authoring_component_parent"

  flow do
    step "child",
      action: Jido.Test.Flow.Authoring.Components.Child,
      params: %{value: input(:value)}

    output %{child: result("child")}
  end
end

defmodule Jido.Test.Flow.Authoring.Components.DoubleParent do
  use Jido.Flow, name: "authoring_double_parent"

  flow do
    step "left",
      action: Jido.Test.Flow.Authoring.Components.Child,
      params: %{value: input(:left)}

    step "right",
      action: Jido.Test.Flow.Authoring.Components.Child,
      params: %{value: input(:right)}

    output %{left: result("left"), right: result("right")}
  end
end

defmodule Jido.Test.Flow.Authoring.Components.ChoiceFlow do
  use Jido.Flow, name: "authoring_choice"

  alias Jido.Test.Flow.Authoring.Components.Echo

  flow do
    choice "route" do
      option "urgent",
        condition: input(:score) >= 90,
        action: Jido.Test.Flow.Authoring.Components.Echo,
        params: %{route: :urgent}

      option "priority",
        condition: input(:score) >= 50,
        action: Jido.Test.Flow.Authoring.Components.Echo,
        params: %{route: :priority}

      otherwise action: Echo, params: %{route: :standard}
    end

    output result("route")
  end
end

defmodule Jido.Test.Flow.Authoring.Components.FinalFlow do
  use Jido.Flow, name: "authoring_final_flow"

  flow do
    step "final",
      action: Jido.Test.Flow.Authoring.Components.Final,
      params: %{value: input(:value)}

    output result("final")
  end
end

defmodule Jido.Test.Flow.Authoring.Components.InvokeFlow do
  use Jido.Flow, name: "authoring_invoke"

  flow do
    invoke "route",
      decision: Jido.Test.Flow.Authoring.Components.Decide,
      expander: Jido.Test.Flow.Authoring.Components.Expand,
      params: %{mode: input(:mode), value: input(:value), target: input(:target)}

    output result("route")
  end
end

defmodule Jido.Test.Flow.Authoring.Components.ParallelFlow do
  use Jido.Flow, name: "authoring_parallel"

  flow do
    parallel "tools" do
      action "echo", Jido.Test.Flow.Authoring.Components.Echo, params: %{value: input(:value)}
    end

    output %{tools: result("tools")}
  end
end

defmodule Jido.Test.Flow.Authoring.Components.HandoffFlow do
  use Jido.Flow, name: "authoring_handoff"

  flow do
    handoff "route", selector: Jido.Test.Flow.Authoring.Components.Expand, params: input()
    output result("route")
  end
end
