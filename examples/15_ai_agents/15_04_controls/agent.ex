defmodule Jido.Examples.AI.Controls.MemberOnly do
  @moduledoc "Allows requests from members."

  use Jido.Action,
    name: "member_only",
    description: "Allow requests from members",
    schema: Jido.Joi.object(%{input: Jido.Joi.string()}),
    output_schema: Jido.Joi.object(%{allowed: Jido.Joi.boolean()})

  @impl Jido.Action
  def run(_params, %{role: :member}), do: {:ok, %{allowed: true}}
  def run(_params, _context), do: {:error, :access_denied}
end

defmodule Jido.Examples.AI.Controls.Agent do
  @moduledoc "An AI Agent with bounded execution and per-request tool policy."

  use Jido.AI.Agent, name: "controls_example"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "openai:gpt-4o-mini"
      instructions "Answer with a source marker."

      limits do
        elapsed_ms(5_000)
        model_calls 1
        tool_rounds 0
        tool_calls 1
      end
    end

    tools do
      action Jido.Examples.AI.Controls.MemberOnly
    end
  end
end
