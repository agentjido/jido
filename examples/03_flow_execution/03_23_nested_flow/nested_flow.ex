defmodule Jido.Examples.NestedFlow do
  @moduledoc "Nested Flow contracts run within one Agent Turn and one commit."

  alias Jido.Joi

  use Jido.Agent, name: "workflow_nested_agent"

  state do
    schema Joi.object(%{result: Joi.map() |> Joi.default(%{})})
  end

  routes do
    signal_source "/workflow"

    route "workflow.nested", Jido.Examples.NestedFlow.Pipeline, as: :draft_and_review
  end
end

defmodule Jido.Examples.NestedFlow.Child do
  @moduledoc "A reusable child Flow with its own input and output contract."

  alias Jido.Joi

  use Jido.Flow,
    name: "workflow_nested_child",
    schema:
      Joi.object(%{
        text: Joi.string() |> Joi.min(1),
        role: Joi.enum([:writer, :editor])
      }),
    output_schema: Joi.object(%{text: Joi.string() |> Joi.min(1), request: Joi.string()})

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

  alias Jido.Joi

  use Jido.Flow,
    name: "workflow_nested_parent",
    schema: Joi.object(%{text: Joi.string()}),
    output_schema:
      Joi.object(%{
        result: Joi.object(%{text: Joi.string() |> Joi.min(1), request: Joi.string()})
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
