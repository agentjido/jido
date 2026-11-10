defmodule Jido.Examples.NestedFlow do
  @moduledoc "Nested Flow contracts run within one Agent Turn and one commit."
  use Jido.Agent, name: "workflow_nested_agent"

  state do
    schema Jido.Joi.object(%{result: Jido.Joi.map() |> Jido.Joi.default(%{})})
  end

  routes do
    signal_source "/workflow"

    route "workflow.nested", Jido.Examples.NestedFlow.Pipeline, as: :draft_and_review
  end
end

defmodule Jido.Examples.NestedFlow.Child do
  @moduledoc "A reusable child Flow with its own input and output contract."
  use Jido.Flow,
    name: "workflow_nested_child",
    schema:
      Jido.Joi.object(%{
        text: Jido.Joi.string() |> Jido.Joi.min(1),
        role: Jido.Joi.enum([:writer, :editor])
      }),
    output_schema: Jido.Joi.object(%{text: Jido.Joi.string() |> Jido.Joi.min(1), request: Jido.Joi.string()})

  flow do
    step "write", [text <- input(:text), role <- input(:role)], inline: [context: context] do
      {:ok,
       %{
         text: text <> ":" <> Atom.to_string(role),
         request: Map.get(context, :request, "none")
       }}
    end

    output result("write")
  end
end

defmodule Jido.Examples.NestedFlow.Pipeline do
  @moduledoc "Two instances of the same child Flow have separate result scopes."

  use Jido.Flow,
    name: "workflow_nested_parent",
    schema: Jido.Joi.object(%{text: Jido.Joi.string()}),
    output_schema:
      Jido.Joi.object(%{
        result: Jido.Joi.object(%{text: Jido.Joi.string() |> Jido.Joi.min(1), request: Jido.Joi.string()})
      })

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
