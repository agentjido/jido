defmodule Jido.AI.Reasoning.Actions.RecordModelAttempt do
  alias Jido.Joi
  @moduledoc "Records one model attempt and any accepted assistant message."

  alias Jido.AI.{Context, Thread.Projection}
  alias Jido.AI.Context.Snapshot

  use Jido.Action,
    id: "jido.ai/reasoning/actions/record-model-attempt",
    vsn: 1,
    name: "jido_ai_record_model_attempt",
    description: "Record a model attempt in the canonical Session",
    schema: Joi.map(),
    output_schema: Joi.map()

  @impl Jido.Action
  def run(%{turn: turn, outcome: %{status: :budget} = outcome} = params, _context) do
    {:ok,
     %{
       turn:
         turn
         |> Map.put(:model_outcome, outcome)
         |> Map.put(:output_allowed, params.output_allowed)
         |> Map.put(:output_reason, params.output_reason)
     }}
  end

  def run(params, _context) do
    turn = params.turn
    outcome = params.outcome
    at = System.system_time(:millisecond)
    refs = %{request_id: turn.request_id, run_id: turn.run_id}

    before_snapshot =
      params.context
      |> Snapshot.new(stage: :prepared, content: :none)
      |> Snapshot.encode()

    after_snapshot =
      params.context
      |> Snapshot.new(content: :none)
      |> Snapshot.encode()

    attempt = %{
      version: 1,
      status: outcome.status,
      reasoning: Map.get(params, :reasoning),
      model: outcome.model,
      req_llm_request_id: outcome[:req_llm_request_id],
      model_index: turn.model_index,
      model_call: turn.model_calls,
      model_attempt: turn.model_attempt,
      tool_rounds: turn.tool_rounds,
      output_allowed: params.output_allowed,
      output_reason: params.output_reason,
      outcome: portable_outcome(outcome),
      prompt_cache: outcome.prompt_cache,
      context: %{
        format: "jido.ai.context.snapshot+json",
        before: before_snapshot,
        after: after_snapshot
      }
    }

    session =
      turn.session
      |> Jido.Session.decode!()
      |> Projection.observe(:ai_model_attempt, attempt, refs, at)

    persist_message = Map.get(params, :persist_message, true)

    with {:ok, session} <-
           maybe_append_assistant(
             session,
             outcome,
             params.context,
             params.output_allowed and persist_message,
             refs,
             at
           ) do
      {:ok,
       %{
         turn:
           turn
           |> Map.put(:session, Jido.Session.encode(session))
           |> Map.update!(:model_attempts, &(&1 ++ [attempt]))
           |> Map.put(:model_outcome, outcome)
           |> Map.put(:output_allowed, params.output_allowed)
           |> Map.put(:output_reason, params.output_reason)
       }}
    end
  end

  defp maybe_append_assistant(
         session,
         %{status: :ok, kind: :final_answer, output: output} = outcome,
         %Context{result: {:ok, %ReqLLM.Response{message: %ReqLLM.Message{} = message}}},
         true,
         refs,
         at
       )
       when not is_nil(output) do
    if structured_output_message?(message),
      do: append_outcome_assistant(session, outcome, refs, at),
      else: append_response_assistant(session, message, refs, at)
  end

  defp maybe_append_assistant(
         session,
         %{status: :ok},
         %Context{result: {:ok, %ReqLLM.Response{message: %ReqLLM.Message{} = message}}},
         true,
         refs,
         at
       ) do
    append_response_assistant(session, message, refs, at)
  end

  defp maybe_append_assistant(session, %{status: :ok} = outcome, _context, true, refs, at) do
    append_outcome_assistant(session, outcome, refs, at)
  end

  defp maybe_append_assistant(session, _outcome, _context, _allowed, _refs, _at),
    do: {:ok, session}

  defp append_outcome_assistant(session, outcome, refs, at) do
    Projection.append(
      session,
      %{
        role: :assistant,
        content: assistant_content(outcome),
        tool_calls: outcome.tool_calls,
        metadata: %{
          response_id: outcome.response_id,
          req_llm_request_id: outcome[:req_llm_request_id],
          model: outcome.model,
          finish_reason: outcome.finish_reason,
          usage: outcome.usage
        }
      },
      refs,
      at
    )
  end

  defp append_response_assistant(session, message, refs, at),
    do: Projection.append(session, message, refs, at)

  defp structured_output_message?(message) do
    calls = Map.get(message, :tool_calls, []) || []
    calls != [] and Enum.all?(calls, &structured_output_call?/1)
  end

  defp structured_output_call?(call) do
    Map.get(call, :name) == "structured_output" or
      call |> Map.get(:function, %{}) |> Map.get(:name) == "structured_output"
  end

  defp portable_outcome(%{status: :ok} = outcome) do
    Map.take(outcome, [
      :status,
      :kind,
      :finish_reason,
      :text,
      :output,
      :tool_calls,
      :req_llm_request_id,
      :response_id,
      :model,
      :usage,
      :started_at_ms,
      :completed_at_ms
    ])
  end

  defp portable_outcome(outcome) do
    Map.take(outcome, [
      :status,
      :category,
      :retryable,
      :reason,
      :model,
      :usage,
      :started_at_ms,
      :completed_at_ms
    ])
  end

  defp assistant_content(%{text: text}) when is_binary(text) and text != "", do: text
  defp assistant_content(%{output: output}) when not is_nil(output), do: JSON.encode!(output)
  defp assistant_content(_outcome), do: ""
end
