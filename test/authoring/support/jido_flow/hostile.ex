defmodule Jido.Test.Flow.Authoring.Hostile.Watch do
  use Jido.Action, name: "authoring_watch"

  @impl true
  def run(params, context) do
    if observer = context[:observer], do: send(observer, {:hostile_action, params})
    {:ok, params}
  end
end

defmodule Jido.Test.Flow.Authoring.Hostile.BadState do
  use Jido.Action, name: "authoring_bad_state"

  @impl true
  def run(_params, context) do
    if observer = context[:observer], do: send(observer, :bad_state_called)
    {:ok, %{count: "wrong type"}}
  end
end

defmodule Jido.Test.Flow.Authoring.Hostile.ChoiceNonBoolean do
  use Jido.Flow, name: "authoring_non_boolean_choice"

  alias Jido.Test.Flow.Authoring.Hostile.Watch

  flow do
    choice "route" do
      option "selected",
        condition: input(:condition),
        action: Jido.Test.Flow.Authoring.Hostile.Watch,
        params: %{branch: :selected}

      otherwise action: Watch, params: %{branch: :fallback}
    end

    output result("route")
  end
end

defmodule Jido.Test.Flow.Authoring.Hostile.IterateInitial do
  use Jido.Flow, name: "authoring_bad_initial_state"

  flow do
    iterate "counter" do
      state Jido.Joi.object(%{count: Jido.Joi.integer()}), initial: %{count: input(:seed)}
      action Jido.Test.Flow.Authoring.Hostile.Watch
      params %{count: state(:count)}
      update %{count: body_result(:count)}
      repeat 1
    end

    output %{counter: result("counter")}
  end
end

defmodule Jido.Test.Flow.Authoring.Hostile.IterateReplacement do
  use Jido.Flow, name: "authoring_bad_replacement_state"

  flow do
    iterate "counter" do
      state Jido.Joi.object(%{count: Jido.Joi.integer()}), initial: %{count: 0}
      action Jido.Test.Flow.Authoring.Hostile.BadState
      params %{count: state(:count)}
      update %{count: body_result(:count)}
      repeat 2
    end

    output %{counter: result("counter")}
  end
end

defmodule Jido.Test.Flow.Authoring.Hostile.IterateCondition do
  use Jido.Flow, name: "authoring_bad_iterate_condition"

  flow do
    iterate "counter" do
      state Jido.Joi.object(%{count: Jido.Joi.integer()}), initial: %{count: 0}
      action Jido.Test.Flow.Authoring.Hostile.Watch
      params %{count: state(:count)}
      update %{count: body_result(:count)}
      while input(:condition)
      max_iterations 2
    end

    output %{counter: result("counter")}
  end
end

defmodule Jido.Test.Flow.Authoring.Hostile.ReduceInitial do
  use Jido.Flow, name: "authoring_reduce_initial"

  flow do
    reduce "fold" do
      collection input(:items)
      initial input(:initial)
      action Jido.Test.Flow.Authoring.Components.Fold
      params %{acc: accumulator(:value), item: item()}
    end

    output result("fold")
  end
end

defmodule Jido.Test.Flow.Authoring.Hostile.Diamond do
  use Jido.Flow, name: "authoring_diamond"

  flow do
    step "sink",
      action: Jido.Test.Flow.Authoring.Hostile.Watch,
      needs: ["left"],
      params: %{id: "sink", value: result("right", :value)}

    step "left",
      action: Jido.Test.Flow.Authoring.Hostile.Watch,
      needs: ["root"],
      params: %{id: "left", value: input(:value)}

    step "right",
      action: Jido.Test.Flow.Authoring.Hostile.Watch,
      params: %{id: "right", value: result("root", :value)}

    step "root",
      action: Jido.Test.Flow.Authoring.Hostile.Watch,
      params: %{id: "root", value: input(:value)}

    output %{value: result("sink", :value)}
  end
end

defmodule Jido.Test.Flow.Authoring.Hostile.Continues do
  use Jido.Action, name: "authoring_illegal_continuation"

  @impl true
  def run(params, context) do
    if observer = context[:observer], do: send(observer, :attempted_continuation)
    {:continue, params, Jido.Test.Flow.Authoring.Hostile.Watch}
  end
end

defmodule Jido.Test.Flow.Authoring.Hostile.Loop do
  use Jido.Action, name: "authoring_continuation_loop"

  @impl true
  def run(params, context) do
    if observer = context[:observer], do: send(observer, {:loop_started, params.value})
    {:continue, params, __MODULE__}
  end
end

defmodule Jido.Test.Flow.Authoring.Hostile.ValidatedFinal do
  use Jido.Action,
    name: "authoring_validated_final",
    output_schema: Jido.Joi.object(%{value: Jido.Joi.integer(), label: Jido.Joi.string()})

  @impl true
  def run(%{value: value}, context), do: {:ok, %{value: value, label: context.label}}
end

defmodule Jido.Test.Flow.Authoring.Hostile.ValidatedFinalFlow do
  use Jido.Flow,
    name: "authoring_validated_final_flow",
    output_schema: Jido.Joi.object(%{value: Jido.Joi.integer(), label: Jido.Joi.string()})

  flow do
    step "final",
      action: Jido.Test.Flow.Authoring.Hostile.Watch,
      params: %{value: input(:value), label: context(:label)}

    output result("final")
  end
end

defmodule Jido.Test.Flow.Authoring.Hostile.SchemaProbe do
  use Jido.Action,
    name: "authoring_schema_probe",
    schema: Jido.Joi.object(%{value: Jido.Joi.integer()}),
    output_schema: Jido.Joi.object(%{value: Jido.Joi.integer()})

  @impl true
  def run(%{value: value}, context) do
    if observer = context[:observer], do: send(observer, :schema_first_called)

    if context[:bad_action_output],
      do: {:ok, %{value: "bad"}},
      else: {:ok, %{value: value}}
  end
end

defmodule Jido.Test.Flow.Authoring.Hostile.SchemaPipeline do
  use Jido.Flow,
    name: "authoring_schema_pipeline",
    schema:
      Jido.Joi.object(%{
        flag: Jido.Joi.boolean() |> Jido.Joi.default(true),
        value: Jido.Joi.any() |> Jido.Joi.default(1),
        child: Jido.Joi.any() |> Jido.Joi.default(2),
        root_output: Jido.Joi.any() |> Jido.Joi.default(3)
      }),
    output_schema: Jido.Joi.object(%{value: Jido.Joi.integer()})

  flow do
    step "first",
      action: Jido.Test.Flow.Authoring.Hostile.SchemaProbe,
      params: %{value: input(:value)}

    step "child",
      action: Jido.Test.Flow.Authoring.Components.Child,
      params: %{value: input(:child)},
      needs: ["first"]

    step "after",
      action: Jido.Test.Flow.Authoring.Hostile.Watch,
      params: %{phase: "after", value: input(:root_output)},
      needs: ["child"]

    output %{value: result("after", :value)}
  end
end
