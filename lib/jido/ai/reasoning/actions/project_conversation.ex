defmodule Jido.AI.Reasoning.Actions.ProjectConversation do
  @moduledoc "Projects the canonical Thread into one model request."

  alias Jido.AI.{Context, Thread.Projection}

  use Jido.Action,
    id: "jido.ai/reasoning/actions/project-conversation",
    vsn: 1,
    name: "jido_ai_project_conversation",
    description: "Project Session history into model messages",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{turn: turn}, _context) do
    with {:ok, session} <- Jido.Session.decode(turn.session),
         {:ok, projection} <- Projection.context(session, turn.context_window),
         {:ok, req_llm_context} <- compose(projection.context, turn),
         {:ok, context} <- Context.new(req_llm_context, metadata: metadata(session, projection, turn)) do
      {:ok, %{turn: turn, context: context}}
    end
  end

  defp compose(context, turn) do
    messages =
      instruction_messages(turn.instructions) ++
        context.messages ++ repair_messages(turn.repair_instruction)

    ReqLLM.Context.validate(%{context | messages: messages})
  end

  defp instruction_messages(nil), do: []
  defp instruction_messages(""), do: []

  defp instruction_messages(instructions) do
    [
      ReqLLM.Context.system(instructions,
        metadata: %{jido: %{source: %{type: :agent_instructions}}}
      )
    ]
  end

  defp repair_messages(nil), do: []
  defp repair_messages(""), do: []

  defp repair_messages(instructions) do
    [
      ReqLLM.Context.system(instructions,
        metadata: %{jido: %{source: %{type: :output_repair}}}
      )
    ]
  end

  defp metadata(session, projection, turn) do
    %{
      source: %{
        session_id: session.id,
        session_rev: session.rev,
        thread_id: session.thread.id,
        thread_rev: session.thread.rev
      },
      call: %{
        request_id: turn.request_id,
        run_id: turn.run_id,
        model_call: turn.model_calls + 1
      },
      projection: %{
        limits: turn.context_window,
        decisions: projection.decisions,
        available_messages: projection.available_messages,
        included_messages: projection.included_messages,
        dropped_messages: projection.dropped_messages,
        first_seq: projection.first_seq,
        last_seq: projection.last_seq
      }
    }
  end
end
