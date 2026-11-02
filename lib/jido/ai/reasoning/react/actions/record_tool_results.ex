defmodule Jido.AI.Reasoning.ReAct.Actions.RecordToolResults do
  @moduledoc "Appends ordered Parallel tool results to the Session."

  alias Jido.AI.{Thread.Projection, ToolResult}

  use Jido.Action,
    id: "jido.ai/reasoning/react/actions/record-tool-results",
    vsn: 1,
    name: "jido_ai_react_record_tool_results",
    description: "Record tool results and continue the Agent graph",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{turn: turn, results: results}, _context) do
    session_result =
      Enum.reduce_while(
        results,
        {:ok, Jido.Session.decode!(turn.session), []},
        fn result, {:ok, session, attempts} ->
          execution = execution(result)
          normalized = ToolResult.normalize(execution.outcome, turn.max_tool_output_bytes)
          refs = refs(turn, result.id)
          attempt = tool_attempt(turn, result, execution, normalized)
          session = Projection.observe(session, :ai_tool_attempt, attempt, refs, execution.completed_at_ms)

          message = %{
            role: :tool,
            content: normalized.content_parts || "",
            name: result.name,
            tool_call_id: result.id,
            output: normalized.model_content,
            metadata: message_metadata(normalized)
          }

          case Projection.append(session, message, refs, execution.completed_at_ms) do
            {:ok, next} -> {:cont, {:ok, next, attempts ++ [attempt]}}
            error -> {:halt, error}
          end
        end
      )

    with {:ok, session, attempts} <- session_result do
      errors = Enum.count(attempts, &(&1.status == :error))

      next_turn = %{
        turn
        | session: Jido.Session.encode(session),
          model_attempt: 0,
          tool_rounds: turn.tool_rounds + 1,
          tool_call_count: turn.tool_call_count + length(results),
          tool_error_count: turn.tool_error_count + errors,
          tool_attempts: turn.tool_attempts ++ attempts,
          model_outcome: nil
      }

      {:ok, %{turn: next_turn}}
    end
  end

  defp execution(%{outcome: %{status: :ok, value: %{outcome: outcome} = execution}})
       when is_map(outcome),
       do: execution

  defp execution(result) do
    now = System.system_time(:millisecond)

    %{
      version: 1,
      call: %{id: result.id, name: result.name, arguments: %{}},
      tool: %{kind: :unknown, name: result.name},
      outcome: outer_outcome(result.outcome),
      started_at_ms: now,
      completed_at_ms: now,
      duration_ms: 0,
      effects_count: 0
    }
  end

  defp outer_outcome(%{status: :error, error: error}), do: %{status: :error, error: error}
  defp outer_outcome(_outcome), do: %{status: :error, error: :invalid_tool_execution}

  defp tool_attempt(turn, result, execution, normalized) do
    %{
      version: 1,
      tool_call_id: result.id,
      tool_name: result.name,
      tool: execution.tool,
      status: normalized.status,
      input: execution.call.arguments,
      output: normalized.model_content,
      content: normalized.content_parts,
      error: normalized.error,
      metadata: normalized.metadata,
      result_metadata: normalized.result_metadata,
      started_at_ms: execution.started_at_ms,
      completed_at_ms: execution.completed_at_ms,
      duration_ms: execution.duration_ms,
      effects_count: execution.effects_count,
      tool_round: turn.tool_rounds + 1,
      review: review(turn, result.name)
    }
  end

  defp review(turn, name) do
    required = name in Map.get(turn, :review_tools, [])
    %{required: required, status: if(required, do: :approved, else: :not_required)}
  end

  defp message_metadata(normalized) do
    normalized.metadata
    |> Map.put(:status, normalized.status)
    |> maybe_put(:tool_result_metadata, normalized.result_metadata)
  end

  defp refs(turn, tool_call_id) do
    %{request_id: turn.request_id, run_id: turn.run_id, tool_call_id: tool_call_id}
  end

  defp maybe_put(map, _key, value) when value == %{}, do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
