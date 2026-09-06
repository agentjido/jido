defmodule Jido.Examples.NestedFlow.Write do
  @moduledoc false
  use Jido.Action, name: "workflow_nested_write"

  def run(input, context) do
    Jido.Examples.Workflow.Observation.record(context, {:child, input.role}, %{
      input: input,
      request: context[:request],
      agent: context.agent_id
    })

    cond do
      context[:fail_role] == input.role ->
        {:error, Jido.Action.Error.execution_error("child failed", role: input.role)}

      context[:invalid_role] == input.role ->
        {:ok, %{text: "", request: context[:request]}}

      true ->
        {:ok,
         %{
           text: input.text <> ":" <> Atom.to_string(input.role),
           request: Map.get(context, :request, "none")
         }}
    end
  end
end

defmodule Jido.Examples.NestedFlow.Child do
  @moduledoc "A reusable child Flow with its own input and output contract."
  use Jido.Flow,
    name: "workflow_nested_child",
    schema: Zoi.object(%{text: Zoi.string(), role: Zoi.enum([:writer, :editor])}),
    output_schema: Zoi.object(%{text: Zoi.string() |> Zoi.min(1), request: Zoi.string()})

  flow do
    step "write", action: Jido.Examples.NestedFlow.Write, params: input()
    output result("write")
  end
end

defmodule Jido.Examples.NestedFlow.Pipeline do
  @moduledoc "Two instances of the same child Flow have separate result scopes."
  use Jido.Flow, name: "workflow_nested_parent"

  flow do
    step "draft",
      action: Jido.Examples.NestedFlow.Child,
      params: %{text: input(:text), role: :writer}

    step "review",
      action: Jido.Examples.NestedFlow.Child,
      params: %{text: result("draft", :text), role: :editor}

    output %{result: result("review")}
  end
end

defmodule Jido.Examples.NestedFlow do
  @moduledoc "Nested Flow contracts run within one Agent Turn and one commit."
  use Jido.Agent, name: "workflow_nested_agent"

  agent do
    schema Zoi.object(%{result: Zoi.map() |> Zoi.default(%{})})
  end

  routes do
    signal_source "/workflow"

    route "workflow.nested", Jido.Examples.NestedFlow.Pipeline do
      define :draft_and_review
    end
  end
end
