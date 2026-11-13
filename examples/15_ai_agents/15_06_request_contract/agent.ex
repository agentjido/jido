defmodule Jido.Examples.AI.RequestContract.Lookup do
  @moduledoc "Looks up one value for the request-contract example."

  use Jido.Action,
    name: "request_contract_lookup",
    description: "Look up one named value",
    schema: Jido.Joi.object(%{name: Jido.Joi.string()})

  @impl Jido.Action
  def run(%{name: name}, _context), do: {:ok, %{name: name, value: "known"}}
end

defmodule Jido.Examples.AI.RequestContract.Calculate do
  @moduledoc "Adds two integers for the request-contract example."

  use Jido.Action,
    name: "request_contract_calculate",
    description: "Add two integers",
    schema: Jido.Joi.object(%{left: Jido.Joi.integer(), right: Jido.Joi.integer()})

  @impl Jido.Action
  def run(%{left: left, right: right}, _context), do: {:ok, %{sum: left + right}}
end

defmodule Jido.Examples.AI.RequestContract.Agent do
  @moduledoc "Shows request preparation, tool visibility, results, and events."

  use Jido.AI.Agent, name: "request_contract_example"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "openai:gpt-4o-mini"
      instructions "Answer in one short sentence."

      limits do
        elapsed_ms(10_000)
        tool_rounds 2
        model_calls 3
        tool_calls 2
      end
    end

    tools do
      action Jido.Examples.AI.RequestContract.Lookup
      action Jido.Examples.AI.RequestContract.Calculate
    end
  end
end
