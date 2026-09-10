defmodule Jido.Examples.ReActAgent.CallModel do
  @moduledoc false

  alias Jido.Examples.ReActAgent.Contracts

  use Jido.Action,
    name: "examples_llm_react_call_model",
    schema: Contracts.turn_input()

  alias Jido.Action.Error

  @impl true
  def run(%{steps_remaining: 0, max_steps: max_steps}, _context) do
    {:error, Error.validation_error("ReAct model step limit reached", %{max_steps: max_steps})}
  end

  def run(input, %{agent_state: agent_state} = context) do
    messages = turn_messages(input, agent_state)
    {module, client} = context.model
    steps_remaining = input.steps_remaining - 1

    case module.complete(client, messages) do
      {:ok, {:tool, name, tool_input}} when is_binary(name) ->
        {:ok,
         %{
           kind: :tool,
           tool_name: name,
           tool_input: tool_input,
           messages: messages,
           max_steps: input.max_steps,
           steps_remaining: steps_remaining
         }}

      {:ok, {:answer, answer}} when is_binary(answer) and byte_size(answer) > 0 ->
        {:ok,
         %{
           kind: :answer,
           answer: answer,
           messages: messages,
           max_steps: input.max_steps,
           steps_remaining: steps_remaining
         }}

      {:error, reason} ->
        {:error, reason}

      result ->
        {:error, {:invalid_model_result, result}}
    end
  end

  defp turn_messages(%{new_turn?: true, prompt: prompt}, agent_state) do
    agent_state.messages ++ [%{role: :user, content: prompt}]
  end

  defp turn_messages(%{new_turn?: false, messages: messages}, _agent_state), do: messages
end

defmodule Jido.Examples.ReActAgent.RouteModelDecision do
  @moduledoc false

  use Jido.Action,
    name: "examples_llm_react_route_model_decision",
    schema: Jido.Examples.ReActAgent.Contracts.decision()

  @impl true
  def run(%{kind: :tool} = input, _context) do
    {:continue, input, Jido.Examples.ReActAgent.RunTool}
  end

  def run(%{kind: :answer} = input, _context) do
    {:continue, input, Jido.Examples.ReActAgent.CommitAnswer}
  end
end

defmodule Jido.Examples.ReActAgent.RunTool do
  @moduledoc false

  use Jido.Action,
    name: "examples_llm_react_run_tool",
    schema: Jido.Examples.ReActAgent.Contracts.tool_decision()

  @impl true
  def run(input, context) do
    with {:ok, {module, client}} <- Map.fetch(context.tools, input.tool_name),
         {:ok, result} <- module.run(client, input.tool_input) do
      messages =
        input.messages ++
          [
            %{
              role: :assistant,
              tool_call: %{name: input.tool_name, input: input.tool_input}
            },
            %{role: :tool, name: input.tool_name, content: result}
          ]

      {:continue,
       %{
         prompt: nil,
         messages: messages,
         new_turn?: false,
         max_steps: input.max_steps,
         steps_remaining: input.steps_remaining
       }, Jido.Examples.ReActAgent.ReasonFlow}
    else
      :error -> {:error, {:unknown_tool, input.tool_name}}
      {:error, reason} -> {:error, reason}
    end
  end
end

defmodule Jido.Examples.ReActAgent.CommitAnswer do
  @moduledoc false

  use Jido.Action,
    name: "examples_llm_react_commit_answer",
    schema: Jido.Examples.ReActAgent.Contracts.answer_decision()

  @impl true
  def run(%{answer: answer, messages: messages}, %{agent_state: agent_state}) do
    {:ok,
     %{
       agent_state
       | messages: messages ++ [%{role: :assistant, content: answer}],
         last_answer: answer,
         turns: agent_state.turns + 1
     }}
  end
end

defmodule Jido.Examples.ReActAgent.ReasonFlow do
  @moduledoc "Runs model and tool continuations until the model returns an answer."

  use Jido.Flow,
    name: "examples_llm_react_reason_flow",
    schema: Jido.Examples.ReActAgent.Contracts.turn_input()

  flow do
    dispatch "reason",
      decision: Jido.Examples.ReActAgent.CallModel,
      expander: Jido.Examples.ReActAgent.RouteModelDecision,
      params: %{
        prompt: input(:prompt),
        messages: input(:messages),
        new_turn?: input(:new_turn?),
        max_steps: input(:max_steps),
        steps_remaining: input(:steps_remaining)
      }

    output result("reason")
  end
end
