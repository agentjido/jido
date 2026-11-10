defmodule Jido.Test.Flow.Authoring.Components.MapItem do
  use Jido.Action, name: "authoring_map_item"
  def run(_, _), do: raise("authoring must not run Actions")
end

defmodule Jido.Test.Flow.Authoring.Components.Fold do
  use Jido.Action, name: "authoring_fold"
  def run(_, _), do: raise("authoring must not run Actions")
end

defmodule Jido.Test.Flow.Authoring.Components.Advance do
  use Jido.Action, name: "authoring_advance"
  def run(_, _), do: raise("authoring must not run Actions")
end

defmodule Jido.Test.Flow.Authoring.Components.Echo do
  use Jido.Action, name: "authoring_component_echo"
  def run(_, _), do: raise("authoring must not run Actions")
end

defmodule Jido.Test.Flow.Authoring.Components.Decide do
  use Jido.Action, name: "authoring_decide"
  def run(_, _), do: raise("authoring must not run Actions")
end

defmodule Jido.Test.Flow.Authoring.Components.Expand do
  use Jido.Action, name: "authoring_expand"
  def run(_, _), do: raise("authoring must not run Actions")
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

defmodule Jido.Test.Flow.Authoring.Components.ChoiceFlow do
  use Jido.Flow, name: "authoring_choice"

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

      otherwise action: Jido.Test.Flow.Authoring.Components.Echo,
                params: %{route: :standard}
    end

    output result("route")
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
    handoff "route",
      selector: Jido.Test.Flow.Authoring.Components.Expand,
      params: input()

    output result("route")
  end
end
