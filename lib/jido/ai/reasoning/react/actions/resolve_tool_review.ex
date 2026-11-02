defmodule Jido.AI.Reasoning.ReAct.Actions.ResolveToolReview do
  @moduledoc "Turns a durable wait result into an explicit graph decision."

  alias Jido.AI.{Reasoning.Result, Thread.Projection}

  use Jido.Action,
    id: "jido.ai/reasoning/react/actions/resolve-tool-review",
    vsn: 1,
    name: "jido_ai_react_resolve_tool_review",
    description: "Resolve an approved, denied, or expired tool review",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{turn: turn, decision: decision}, _context) do
    status = review_status(decision.selected)
    at = System.system_time(:millisecond)

    session =
      Projection.observe(
        Jido.Session.decode!(turn.session),
        :ai_review,
        %{
          version: 1,
          status: status,
          selected: decision.selected,
          review_id: turn.review_id,
          decision: decision_payload(decision)
        },
        %{review_id: turn.review_id, request_id: turn.request_id, run_id: turn.run_id},
        at
      )

    turn = %{turn | review_id: nil, session: Jido.Session.encode(session)}

    case status do
      :approved -> {:ok, %{kind: :tools, input: %{turn: turn}}}
      :denied -> {:ok, complete(turn, "tool use was denied")}
      :expired -> {:ok, complete(turn, "tool review expired")}
    end
  end

  defp review_status("approved"), do: :approved
  defp review_status("denied"), do: :denied
  defp review_status("expired"), do: :expired

  defp decision_payload(%{value: value}) when is_map(value) do
    Map.take(value, [:review_id, :request_id, :run_id, :actor_id, :reason])
  end

  defp decision_payload(_decision), do: %{}

  defp complete(turn, reason) do
    %{
      kind: :complete,
      output: %{
        turn: turn,
        result: Result.blocked(:review, reason)
      }
    }
  end
end
