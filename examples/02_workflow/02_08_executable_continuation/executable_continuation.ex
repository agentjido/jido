defmodule Jido.Examples.ExecutableContinuation do
  @moduledoc "One Turn owns Invoke selection and bounded Flow execution."
  use Jido.Agent, name: "workflow_continuation_agent"

  state do
    schema Zoi.object(%{
             value: Zoi.integer() |> Zoi.default(0),
             request: Zoi.string() |> Zoi.default("")
           })
  end

  routes do
    signal_source "/workflow"

    route "workflow.continuation", Jido.Examples.ExecutableContinuation.Pipeline,
      as: :add_repeatedly do
    end
  end
end

defmodule Jido.Examples.ExecutableContinuation.Expand do
  @moduledoc false

  use Jido.Action,
    name: "workflow_continuation_expand",
    schema:
      Zoi.object(%{
        value: Zoi.integer() |> Zoi.min(0),
        remaining: Zoi.integer() |> Zoi.min(0)
      })

  @impl true
  def run(input, _context) do
    target =
      if input.remaining == 0,
        do: Jido.Examples.ExecutableContinuation.Finish,
        else: Jido.Examples.ExecutableContinuation.Repeat

    {:continue, input, target}
  end
end

defmodule Jido.Examples.ExecutableContinuation.Add do
  @moduledoc false

  use Jido.Action,
    name: "workflow_continuation_add",
    schema:
      Zoi.object(%{
        value: Zoi.integer() |> Zoi.min(0),
        remaining: Zoi.integer() |> Zoi.min(1)
      })

  @impl true
  def run(input, _context) do
    {:ok, %{input | value: input.value + 1, remaining: input.remaining - 1}}
  end
end

defmodule Jido.Examples.ExecutableContinuation.Finish do
  @moduledoc false
  use Jido.Action,
    name: "workflow_continuation_finish"

  def run(input, context),
    do: {:ok, %{value: input.value, request: Map.get(context, :request, "none")}}
end

defmodule Jido.Examples.ExecutableContinuation.Repeat do
  @moduledoc "The selected Flow permits at most three additions before one terminal result."
  use Jido.Flow,
    name: "workflow_continuation_repeat"

  flow do
    iterate "add" do
      state Zoi.object(%{value: Zoi.integer(), remaining: Zoi.integer() |> Zoi.min(0)}),
        initial: input()

      action Jido.Examples.ExecutableContinuation.Add
      params state()
      update body_result()
      while state(:remaining) > 0
      max_iterations 3
    end

    step "finish",
      action: Jido.Examples.ExecutableContinuation.Finish,
      params: result("add", :state)

    output result("finish")
  end
end

defmodule Jido.Examples.ExecutableContinuation.Decision do
  @moduledoc false
  use Jido.Action,
    name: "workflow_continuation_decision"

  def run(input, _context), do: {:ok, input}
end

defmodule Jido.Examples.ExecutableContinuation.Pipeline do
  @moduledoc "Invoke selects an Action or bounded Flow in the same Exec call."
  use Jido.Flow,
    name: "workflow_continuation",
    schema:
      Zoi.object(%{value: Zoi.integer() |> Zoi.min(0), remaining: Zoi.integer() |> Zoi.min(0)}),
    output_schema: Zoi.object(%{value: Zoi.integer() |> Zoi.min(0), request: Zoi.string()})

  flow do
    invoke("next",
      decision: Jido.Examples.ExecutableContinuation.Decision,
      expander: Jido.Examples.ExecutableContinuation.Expand,
      params: input()
    )

    output result("next")
  end
end
