defmodule Jido.Examples.Factory.Model do
  @moduledoc "A bounded text and tool loop using ReqLLM directly. Clients stay in caller context."

  alias ReqLLM.{Context, Response, StreamResponse, ToolCall}

  @doc "Returns the model selected for this example."
  def model, do: System.get_env("FACTORY_MODEL", "anthropic:claude-haiku-4-5")

  @doc "Runs at most five model requests and four tools per request."
  def reply(messages, context, tools \\ []) do
    with {:ok, history} <- Context.normalize(messages) do
      if Map.get(context, :stream, false), do: notify(context, :start)
      loop(history, context, tools, 5)
    end
  end

  defp loop(_history, _context, _tools, 0), do: {:error, :model_round_limit}

  defp loop(history, context, tools, remaining) do
    model = Map.get(context, :model, model())

    opts =
      [max_tokens: 1_500, receive_timeout: 30_000]
      |> Keyword.merge(Map.get(context, :llm_opts, []))
      |> Keyword.put(:tools, tools)
      # Keep HTTP inside the Jido-owned task. A finite ReqLLM total timeout
      # starts an unlinked request task under its own supervisor.
      |> Keyword.put(:total_timeout, :infinity)

    with {:ok, response} <- generate(model, history, opts, context) do
      continue(response, history, context, tools, remaining)
    else
      {:error, reason} -> {:error, Jido.Examples.Factory.Error.request(reason, model, opts)}
    end
  end

  defp generate(model, history, opts, %{stream: true} = context) do
    with {:ok, stream} <- ReqLLM.stream_text(model, history, opts) do
      try do
        # Consume once: ReqLLM assembles the complete text and tool arguments.
        StreamResponse.process_stream(stream,
          on_result: fn text -> notify(context, {:delta, text}) end
        )
        |> complete_stream()
      after
        StreamResponse.close(stream)
        notify(context, :round_end)
      end
    end
  end

  defp generate(model, history, opts, _context), do: ReqLLM.generate_text(model, history, opts)

  defp complete_stream({:ok, %{finish_reason: reason}} = result)
       when reason in [:stop, :tool_calls],
       do: result

  defp complete_stream({:ok, _response}) do
    {:error,
     ReqLLM.Error.API.Response.exception(
       reason: "The stream ended before a complete response was received."
     )}
  end

  defp complete_stream({:error, _} = error), do: error

  defp notify(context, event) do
    case Map.get(context, :on_stream) do
      callback when is_function(callback, 2) -> callback.(Map.get(context, :stream_id, ""), event)
      _ -> :ok
    end
  end

  defp continue(response, history, context, tools, remaining) do
    calls = response |> Response.tool_calls() |> Enum.reject(&ToolCall.builtin?/1)

    cond do
      length(calls) > 4 ->
        {:error, :tool_call_limit}

      calls != [] and remaining == 1 ->
        {:error, :model_round_limit}

      calls != [] ->
        results = Enum.map(calls, &execute(&1, tools))

        with {:ok, next} <- Context.append_tool_exchange(history, response, results) do
          loop(next, context, tools, remaining - 1)
        end

      true ->
        case Response.text(response) do
          text when is_binary(text) and byte_size(text) > 0 -> {:ok, %{text: text}}
          _ -> {:error, :empty_model_response}
        end
    end
  end

  defp execute(call, tools) do
    result =
      case ToolCall.execute(call, tools) do
        {:ok, value} ->
          %{ok: true, result: value}

        {:error, %Jido.Action.Error.InvalidInputError{message: message}} ->
          %{ok: false, error: message}

        {:error, _reason} ->
          %{ok: false, error: "Tool input or operation was rejected."}
      end

    Context.tool_result(call.id, ToolCall.name(call), result)
  end
end
