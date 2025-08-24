defmodule Jido.BasicAgent.ResponseAction do
  @moduledoc """
  Generates conversational responses for BasicAgent.

  This action handles the core logic of interpreting messages and generating
  appropriate responses, including math calculations, greetings, and help.
  """

  use Jido.Action,
    name: "basic_response",
    description: "Generates conversational responses for BasicAgent",
    schema: [
      message: [type: :string, required: true, doc: "The message to respond to"],
      context: [type: :map, default: %{}, doc: "Additional context for response generation"]
    ]

  @impl true
  def run(%{message: message} = params, context) do
    conversation_context = Map.get(params, :context, %{})

    response =
      cond do
        math_expression?(message) ->
          handle_math_expression(message)

        greeting?(message) ->
          handle_greeting(message, conversation_context)

        help_request?(message) ->
          handle_help_request()

        true ->
          handle_general_message(message)
      end

    # Return response with conversation directive
    conversation_directive = create_conversation_directive(message, response, context)

    {:ok, %{response: response}, conversation_directive}
  end

  ## Message Pattern Detection

  defp math_expression?(message) do
    Regex.match?(~r/^\s*\d+\s*[\+\-\*\/]\s*\d+/, String.trim(message))
  end

  defp greeting?(message) do
    normalized = String.downcase(String.trim(message))
    Enum.any?(["hello", "hi", "hey", "greetings", "howdy"], &String.contains?(normalized, &1))
  end

  defp help_request?(message) do
    normalized = String.downcase(String.trim(message))

    Enum.any?(
      ["help", "what can you do", "capabilities", "commands"],
      &String.contains?(normalized, &1)
    )
  end

  ## Response Handlers

  defp handle_math_expression(expression) do
    case evaluate_math(expression) do
      {:ok, result} -> "#{result}"
      {:error, _} -> "I couldn't calculate that. Please try a simpler expression like '2+2'."
    end
  end

  defp handle_greeting(_message, context) do
    agent_name = Map.get(context, :agent_name, "BasicAgent")

    greetings = [
      "Hello! I'm #{agent_name}. How can I help you today?",
      "Hi there! I'm #{agent_name}. I can help with math and conversation.",
      "Hey! I'm #{agent_name}. What would you like to talk about?",
      "Greetings! I'm #{agent_name}. I'm here to help."
    ]

    Enum.random(greetings)
  end

  defp handle_help_request do
    """
    I can help with:
    • Math calculations (try '2+2' or '15 * 3')
    • Simple conversation
    • Custom actions you register
    • Type 'hello' to get a friendly greeting

    Just type what you need and I'll do my best to help!
    """
  end

  defp handle_general_message(message) do
    responses = [
      "I understand you said: #{message}",
      "That's interesting. You mentioned: #{extract_key_topic(message)}",
      "I received your message about #{extract_key_topic(message)}.",
      "Thanks for sharing: #{String.slice(message, 0..50)}#{if String.length(message) > 50, do: "...", else: ""}",
      "I'm processing what you said: #{extract_key_topic(message)}"
    ]

    Enum.random(responses)
  end

  ## Utility Functions

  defp evaluate_math(expression) do
    try do
      # Simple evaluation for basic math
      clean_expr = String.trim(expression)
      {result, _} = Code.eval_string(clean_expr)
      {:ok, result}
    rescue
      _ -> {:error, "Invalid expression"}
    end
  end

  defp extract_key_topic(message) do
    # Extract first few meaningful words
    message
    |> String.split()
    |> Enum.take(3)
    |> Enum.join(" ")
  end

  defp create_conversation_directive(user_message, response, _context) do
    # Create directive to append to conversation history using update function
    %Jido.Agent.Directive.StateModification{
      op: :update,
      path: [:conversation],
      value: fn conversation ->
        new_messages = [
          %{role: :user, content: user_message, timestamp: DateTime.utc_now()},
          %{role: :assistant, content: response, timestamp: DateTime.utc_now()}
        ]

        (conversation || []) ++ new_messages
      end
    }
  end
end
