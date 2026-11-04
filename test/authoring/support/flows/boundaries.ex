defmodule JidoActionTest.Authoring.Boundaries.Inline do
  use Jido.Flow, name: "authoring_inline"

  flow do
    step "none", [] do
      {:ok, %{value: 1}}
    end

    step "one", value <- input(:value) do
      {:ok, %{value: value + 1}}
    end

    step "many", [left <- result("one", :value), right <- input(:right)] do
      {:ok, %{value: left + right}}
    end

    step "map", %{value: value} <- result("many") do
      {:ok, %{value: value * 2}}
    end

    step "ctx", value <- result("map", :value), inline: [context: ctx] do
      {:ok, %{value: value, label: ctx.label}}
    end

    output %{none: result("none"), final: result("ctx")}
  end
end

defmodule JidoActionTest.Authoring.Boundaries.Expressions do
  use Jido.Flow, name: "authoring_expressions"

  flow do
    step "echo",
      action: JidoActionTest.Authoring.Components.Echo,
      params: %{name: input(:name)}

    output %{
      total: input(:a) * input(:b) + 1,
      flags: [input(:enabled) and not context(:paused), input(:maybe) == nil],
      message: "Hi " <> result("echo", :name)
    }
  end
end

defmodule JidoActionTest.Authoring.Boundaries.Stored do
  use Jido.Flow, name: "authoring_saved"

  flow do
    step "echo",
      action: JidoActionTest.Authoring.Components.Echo,
      params: %{value: input(:value)}

    output %{value: result("echo", :value)}
  end
end

defmodule JidoActionTest.Authoring.Boundaries.Bomb do
  use Jido.Action, name: "authoring_decode_must_not_run"

  @impl true
  def run(_params, _context), do: raise("authoring validation ran Action work")
end

defmodule JidoActionTest.Authoring.Boundaries.Inert do
  use Jido.Flow, name: "authoring_inert"

  flow do
    step "bomb",
      action: JidoActionTest.Authoring.Boundaries.Bomb,
      params: %{value: input(:value)}

    output %{value: result("bomb", :value)}
  end
end

defmodule JidoActionTest.Authoring.Boundaries.Paths do
  use Jido.Flow, name: "authoring_paths"

  flow do
    step "echo",
      action: JidoActionTest.Authoring.Components.Echo,
      params: %{value: input([:payload, "items", 0])}

    output result("echo")
  end
end

defmodule JidoActionTest.Authoring.Boundaries.RawAction do
  use Jido.Action, name: "authoring_raw_action"

  @impl true
  def run(_params, _context), do: {:ok, Jido.Action.Output.raw("done")}
end

defmodule JidoActionTest.Authoring.Boundaries.RawFlow do
  use Jido.Flow, name: "authoring_raw_flow"

  flow do
    step "raw", action: JidoActionTest.Authoring.Boundaries.RawAction, params: %{}
    output result("raw")
  end
end

defmodule JidoActionTest.Authoring.Boundaries.ScalarFlow do
  use Jido.Flow, name: "authoring_scalar_flow"

  flow do
    step "echo",
      action: JidoActionTest.Authoring.Components.Echo,
      params: %{value: input(:value)}

    output result("echo", :value)
  end
end

defmodule JidoActionTest.Authoring.Boundaries.SchemaAction do
  use Jido.Action,
    name: "authoring_schema_action",
    schema: Jido.Joi.object(%{value: Jido.Joi.integer()}),
    output_schema: Jido.Joi.object(%{value: Jido.Joi.integer()})

  @impl true
  def run(%{value: value}, %{mode: :bad_output}), do: {:ok, %{value: Integer.to_string(value)}}

  def run(%{value: value}, _context),
    do: {:ok, %{value: value + 1}, [:schema_effect]}
end

defmodule JidoActionTest.Authoring.Boundaries.SchemaFlow do
  use Jido.Flow,
    name: "authoring_schema_flow",
    schema: Jido.Joi.object(%{value: Jido.Joi.any() |> Jido.Joi.default(1)}),
    output_schema: Jido.Joi.object(%{value: Jido.Joi.integer()})

  flow do
    step "work",
      action: JidoActionTest.Authoring.Boundaries.SchemaAction,
      params: %{value: input(:value)}

    output result("work")
  end
end

defmodule JidoActionTest.Authoring.Boundaries.BadRootOutput do
  use Jido.Flow,
    name: "authoring_bad_root_output",
    output_schema: Jido.Joi.object(%{value: Jido.Joi.integer()})

  flow do
    step "work",
      action: JidoActionTest.Authoring.Boundaries.SchemaAction,
      params: %{value: input(:value)}

    output %{value: "bad"}
  end
end
