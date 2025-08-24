defmodule Jido.SimpleAgent.RuleBasedReasoner do
  @moduledoc """
  A simple rule-based reasoner that uses pattern matching to determine responses.

  This reasoner can:
  - Detect mathematical expressions and route them to the Eval action
  - Handle basic conversational patterns
  - Process tool results and provide responses
  """

  @behaviour Jido.SimpleAgent.Reasoner

  @impl Jido.SimpleAgent.Reasoner
  def reason(message, state) when is_binary(message) do
    # Handle string messages directly
    reason_user_message(message, state)
  end

  def reason(message, state) do
    case message do
      %{role: :user, content: content} ->
        reason_user_message(content, state)

      %{role: :tool} ->
        reason_tool_result(state)

      nil ->
        {:respond, "Hello! How can I help you?"}

      _ ->
        {:respond, "I'm not sure how to handle that message type."}
    end
  end

  # Handle user messages  
  defp reason_user_message(content, _state) do
    content = String.downcase(String.trim(content))

    cond do
      # Basic conversational patterns (check these first before math)
      Regex.match?(~r/^(?:hi|hello|hey)/, content) ->
        {:respond, "Hello! How can I help you?"}

      Regex.match?(~r/help|i\s+need\s+help/, content) ->
        {:respond, "I can help with math calculations and answer basic questions."}

      Regex.match?(~r/thank|thx/, content) ->
        {:respond, "You're welcome!"}

      Regex.match?(~r/bye|goodbye|see\s+you/, content) ->
        {:respond, "Goodbye! Have a great day!"}

      # Name questions - but not math expressions like "what is 2+3"  
      Regex.match?(~r/what'?s?\s+(?:is\s+)?(?:your\s+)?name/, content) &&
          !Regex.match?(~r/[\d\+\-\*\/\(\)]/, content) ->
        {:respond, "I'm a Jido SimpleAgent!"}

      Regex.match?(~r/what\s+time/, content) ->
        {:respond, "I don't have access to the current time, but I can help with calculations!"}

      Regex.match?(~r/weather/, content) ->
        {:respond, "I can't check the weather, but I'm great with math!"}

      Regex.match?(~r/how\s+are\s+you|status/, content) ->
        {:respond, "I'm running smoothly and ready to help!"}

      Regex.match?(~r/what\s+(?:can\s+)?you\s+do/, content) ->
        {:respond, "I can perform mathematical calculations and have basic conversations."}

      # Math detection - route to Eval action for mathematical expressions
      math_expression?(content) ->
        expression = extract_math_expression(content)
        {:tool_call, Jido.Skills.Arithmetic.Actions.Eval, %{expression: expression}}

      true ->
        {:respond, "I'm not sure about that, but I can help with math calculations!"}
    end
  end

  # Handle tool results - provide response based on the last tool execution
  defp reason_tool_result(state) do
    case get_last_tool_result(state) do
      {Jido.Skills.Arithmetic.Actions.Eval, %{result: result}} ->
        {:respond, "The answer is #{result}"}

      {action_module, result} ->
        {:respond, "The #{action_module} action completed with result: #{inspect(result)}"}

      nil ->
        {:respond, "I completed the requested action."}
    end
  end

  # Check if the content contains a mathematical expression
  defp math_expression?(content) do
    # Look for explicit math keywords followed by any expression, or standalone math expressions
    Regex.match?(~r/(?:what\s+is|calculate|compute|solve)\s+.+/i, content) ||
      Regex.match?(~r/^\s*[\d\+\-\*\/\(\)\s\.]+\s*[\?\.]?\s*$/i, content)
  end

  # Extract the mathematical expression from the content
  defp extract_math_expression(content) do
    case Regex.run(~r/(?:what\s+is|calculate|compute|solve)\s*(.+?)(?:\?|$)/i, content,
           capture: :all_but_first
         ) do
      [expression] ->
        String.trim(expression)

      _ ->
        # If no explicit math phrase, try to find a mathematical expression
        case Regex.run(~r/([\d\+\-\*\/\(\)\s\.]+)/, content) do
          [expression] -> String.trim(expression)
          _ -> content
        end
    end
  end

  # Get the most recent tool result
  defp get_last_tool_result(state) do
    case state.memory.tool_results do
      results when map_size(results) == 0 ->
        nil

      results ->
        # Get the most recent tool result (this is simplified - in a real implementation
        # we might want to track execution order)
        {action, result} = Enum.at(results, -1)
        {action, result}
    end
  end
end
