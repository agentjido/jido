defmodule Jido.AI.Reasoning.ReAct.Actions.RequestToolReview do
  @moduledoc "Publishes one review request before the durable Flow wait."

  alias Jido.AI.Thread.Projection

  use Jido.Action,
    id: "jido.ai/reasoning/react/actions/request-tool-review",
    vsn: 1,
    name: "jido_ai_react_request_tool_review",
    description: "Request approval for one tool group",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{turn: turn}, context) do
    at = System.system_time(:millisecond)
    session = Jido.Session.decode!(turn.session)
    review_id = "review:#{turn.run_id}:#{turn.tool_rounds + 1}"
    expires_at_ms = at + 300_000

    data = %{
      review_id: review_id,
      session_id: session.id,
      thread_id: session.thread.id,
      request_id: turn.request_id,
      run_id: turn.run_id,
      timestamp_ms: at,
      expires_at_ms: expires_at_ms,
      options: [:approved, :denied],
      policy_reason: Map.get(turn.tool_selection, :reason) || "tool review required",
      tool_calls: turn.model_outcome.tool_calls
    }

    _result = dispatch_review_signal(context, data)

    next_session =
      Projection.observe(
        session,
        :ai_review,
        %{
          version: 1,
          status: :requested,
          review_id: review_id,
          expires_at_ms: expires_at_ms,
          options: [:approved, :denied],
          policy_reason: data.policy_reason,
          tool_calls: turn.model_outcome.tool_calls
        },
        %{review_id: review_id, request_id: turn.request_id, run_id: turn.run_id},
        at
      )

    {:ok, %{turn: %{turn | review_id: review_id, session: Jido.Session.encode(next_session)}}}
  end

  defp dispatch_review_signal(context, data) do
    case Map.get(context, :jido_ai_dispatch) do
      nil ->
        :ok

      dispatch ->
        with {:ok, signal} <-
               Jido.Agent.build_signal(context, "jido.ai.review.requested", data) do
          Jido.Signal.Dispatch.dispatch(signal, dispatch)
        end
    end
  end
end
