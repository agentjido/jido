defmodule Jido.Examples.Conversation.FailedAndIncomplete do
  @moduledoc "Builds failed and incomplete exchanges for public projection checks."

  alias Jido.AI.Thread.Projection
  alias Jido.Session

  @doc "Records a user message and a failed request outcome with one run ID."
  def failed_request do
    refs = %{run_id: "failed-run", request_id: "failed-request"}
    session = Session.new(id: "failed-session", now: 100)

    with {:ok, session} <- Projection.append(session, %{role: :user, content: "Fail"}, refs, 101) do
      {:ok,
       Projection.observe(
         session,
         :ai_request_outcome,
         %{status: :failed, reason: "offline failure"},
         refs,
         102
       )}
    end
  end

  @doc "Records a tool request without its required tool result."
  def incomplete_tool_exchange do
    call = ReqLLM.ToolCall.new("lookup-1", "lookup", ~s({"id":"7"}))
    session = Session.new(id: "incomplete-session", now: 200)

    with {:ok, session} <- Projection.append(session, %{role: :user, content: "Look up 7"}, %{}, 201),
         {:ok, session} <-
           Projection.append(
             session,
             %{role: :assistant, content: "", tool_calls: [call]},
             %{},
             202
           ) do
      {:ok, session}
    end
  end
end
