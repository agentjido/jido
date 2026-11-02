defmodule Jido.AI.Reasoning.Actions.FinalizeTurn do
  @moduledoc "Finalizes one graph request and returns the Agent commit envelope."

  alias Jido.AI.{Budget, Telemetry, Thread.Projection}

  use Jido.Action,
    id: "jido.ai/reasoning/actions/finalize-turn",
    vsn: 1,
    name: "jido_ai_finalize_turn",
    description: "Commit the terminal request Session",
    schema: Zoi.object(%{outcome: Zoi.object(%{turn: Zoi.any(), result: Zoi.map()})}),
    output_schema: Zoi.object(%{state: Zoi.map(), response: Zoi.map()})

  @impl Jido.Action
  def run(%{outcome: %{turn: turn, result: result}}, context) do
    completed_at = System.system_time(:millisecond)
    refs = %{request_id: turn.request_id, run_id: turn.run_id}
    budget = Budget.summary(turn, completed_at)

    summary = %{
      version: 1,
      flow: turn.flow,
      status: result.status,
      output: result.output,
      reason_code: result.reason_code,
      reason: result.reason,
      reasoning: result.reasoning,
      started_at_ms: turn.started_at_ms,
      completed_at_ms: completed_at,
      model_calls: turn.model_calls,
      tool_rounds: turn.tool_rounds,
      tool_calls: turn.tool_call_count,
      tool_errors: turn.tool_error_count,
      tool_cycles: Map.get(turn, :tool_cycle_count, 0),
      retries: turn.retries,
      budget: budget,
      reasoning_steps: get_in(result, [:reasoning, :steps_count]),
      usage: turn.usage
    }

    session =
      turn.session
      |> Jido.Session.decode!()
      |> Projection.observe(:ai_request_outcome, summary, refs, completed_at)

    state =
      if Map.get(turn, :session_owner, :agent) == :caller,
        do: turn.agent_state,
        else: Map.put(turn.agent_state, :session, session)

    session_entries =
      session.thread.entries
      |> Enum.drop(Map.get(turn, :session_entry_count, 0))
      |> Enum.map(&Jido.Thread.Entry.encode/1)

    response =
      Map.merge(summary, %{
        request_id: turn.request_id,
        run_id: turn.run_id,
        session_id: session.id,
        thread_id: session.thread.id,
        thread_rev: session.thread.rev,
        session_entries: session_entries,
        usage: turn.usage,
        budget: budget,
        model_attempts: turn.model_attempts,
        tool_attempts: Map.get(turn, :tool_attempts, [])
      })

    Telemetry.record_agent_summary(context, %{
      status: result.status,
      run_id: turn.run_id,
      session_id: session.id,
      thread_id: session.thread.id,
      reason_code: result.reason_code,
      model_calls: turn.model_calls,
      tool_rounds: turn.tool_rounds,
      tool_calls: turn.tool_call_count,
      tool_errors: turn.tool_error_count,
      tool_cycles: Map.get(turn, :tool_cycle_count, 0),
      retries: turn.retries,
      reasoning_steps: get_in(result, [:reasoning, :steps_count]),
      usage: turn.usage
    })

    {:ok, %{state: state, response: response}}
  end
end
