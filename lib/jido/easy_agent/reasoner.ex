defmodule Jido.EasyAgent.Reasoner do
  @moduledoc """
  A reasoner that converts simple messages into Agent.Server instruction plans.

  This reasoner bridges SimpleAgent's conversational interface with Agent.Server's
  instruction-based execution model by analyzing messages and determining what
  actions to take.
  """

  require Logger

  @doc """
  Analyzes a message and determines what instructions to execute.

  Returns either a direct response or a list of instructions to execute.
  """
  @spec reason(String.t(), map()) ::
          {:respond, String.t()}
          | {:instructions, [Jido.Instruction.t()]}
          | {:error, term()}
  def reason(message, state) when is_binary(message) do
    cond do
      math_expression?(message) ->
        create_math_instruction(message)

      greeting?(message) ->
        {:respond, "Hello! I'm #{state.name}. I can help with math and other tasks."}

      help_request?(message) ->
        {:respond,
         "I can help with:\n- Math calculations (like '2+2')\n- General questions\n- And more as I learn!"}

      true ->
        # Default conversational response
        {:respond, generate_conversational_response(message)}
    end
  end

  ## Pattern Detection

  defp math_expression?(message) do
    # Detect simple math expressions
    Regex.match?(~r/^\s*\d+\s*[\+\-\*\/]\s*\d+/, String.trim(message))
  end

  defp greeting?(message) do
    normalized = String.downcase(String.trim(message))
    Enum.any?(["hello", "hi", "hey", "greetings"], &String.contains?(normalized, &1))
  end

  defp help_request?(message) do
    normalized = String.downcase(String.trim(message))
    Enum.any?(["help", "what can you do", "capabilities"], &String.contains?(normalized, &1))
  end

  ## Instruction Creation

  defp create_math_instruction(expression) do
    # Extract the math expression
    clean_expr = String.trim(expression)

    # Create instruction for math evaluation
    instruction = %Jido.Instruction{
      action: Jido.Skills.Arithmetic.Actions.Eval,
      params: %{expression: clean_expr},
      context: %{source: :easy_agent_reasoner}
    }

    {:instructions, [instruction]}
  end

  ## Response Generation

  defp generate_conversational_response(message) do
    responses = [
      "I understand you said: #{message}",
      "That's interesting. You mentioned: #{String.slice(message, 0..50)}#{if String.length(message) > 50, do: "...", else: ""}",
      "I received your message about #{extract_topic(message)}.",
      "Thanks for sharing: #{message}",
      "I'm processing what you said: #{message}"
    ]

    Enum.random(responses)
  end

  defp extract_topic(message) do
    # Simple topic extraction - take first few words
    message
    |> String.split()
    |> Enum.take(3)
    |> Enum.join(" ")
  end
end
