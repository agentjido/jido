defmodule Jido.Examples.AI.ModelHelpers.FastAgent do
  @moduledoc "An Agent with one application-selected model default."

  use Jido.AI.Agent, name: "model_default_example"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "openai:gpt-4o-mini"
    end
  end
end

defmodule Jido.Examples.AI.ModelHelpers.PinnedAgent do
  @moduledoc "An Agent with one pinned provider model name."

  use Jido.AI.Agent, name: "direct_model_example"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "anthropic:claude-haiku-4-5"
    end
  end
end
