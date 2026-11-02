defmodule Jido.AI.Reasoning.Actions.StartRequest do
  @moduledoc "Initializes one request and appends its user message to the Session."

  alias Jido.AI.{Thread.Projection, Toolset, ToolSource, Usage}

  use Jido.Action,
    id: "jido.ai/reasoning/actions/start-request",
    vsn: 1,
    name: "jido_ai_start_request",
    description: "Load conversation state and start one graph request",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(params, context) do
    now = System.system_time(:millisecond)
    static_tools = Toolset.from_context(context)
    agent_state = Map.get(context, :agent_state, %{session: nil})
    request_id = request_id(context)
    run_id = "run_#{Jido.generate_id()}"
    refs = %{request_id: request_id, run_id: run_id}

    with {:ok, session, session_owner} <- session(agent_state, context, now),
         {:ok, dynamic_tools} <- ToolSource.load(context),
         {:ok, selection} <-
           Toolset.select(static_tools ++ dynamic_tools, Map.get(params, :tool_policy, %{})),
         {:ok, session} <-
           Projection.append(session, %{role: :user, content: params.input}, refs, now) do
      review_tools =
        if Map.get(params, :review_tools, false), do: selection.visible, else: selection.review

      review_required = Map.get(params, :review_tools, false) or review_tools != []

      {:ok,
       %{
         agent_state: turn_agent_state(agent_state, session_owner),
         session: Jido.Session.encode(session),
         session_owner: session_owner,
         session_entry_count: session.thread.rev - 1,
         request_id: request_id,
         run_id: run_id,
         flow: Map.get(params, :flow),
         started_at_ms: now,
         input: params.input,
         instructions: params.instructions,
         models: [params.model | Map.get(params, :fallback_models, [])],
         model_index: 0,
         model_attempt: 0,
         model_calls: 0,
         max_model_calls: params.max_model_calls,
         max_elapsed_ms: Map.get(params, :max_elapsed_ms),
         max_input_tokens: Map.get(params, :max_input_tokens),
         max_output_tokens: Map.get(params, :max_output_tokens),
         max_total_tokens: Map.get(params, :max_total_tokens),
         max_total_cost: Map.get(params, :max_total_cost),
         max_retries: Map.get(params, :max_retries, 0),
         retries: 0,
         options: params.options,
         output_schema: Map.get(params, :output_schema),
         prompt_cache: Map.get(params, :prompt_cache, %{enabled: false}),
         stream: Map.get(params, :stream, false),
         review_required: review_required,
         review_tools: review_tools,
         review_id: nil,
         repair_instruction: nil,
         context_window: params.context_window,
         tool_rounds: 0,
         max_tool_rounds: Map.get(params, :max_tool_rounds, 0),
         tool_call_count: 0,
         tool_error_count: 0,
         tool_cycle_count: 0,
         previous_tool_signature: nil,
         max_tool_calls: Map.get(params, :max_tool_calls, 0),
         max_tool_output_bytes: Map.get(params, :max_tool_output_bytes, 16_384),
         tools: selection.tools,
         tool_selection:
           selection
           |> Map.drop([:actions, :tools])
           |> Map.put(:review, review_tools),
         tool_requirement: selection.requirement,
         model_outcome: nil,
         usage: Usage.zero(),
         model_attempts: [],
         tool_attempts: []
       }}
    end
  end

  defp session(_agent_state, %{jido_ai_session: value}, _now) do
    with {:ok, session} <- Jido.Session.decode(value),
         true <- Jido.Session.open?(session) do
      {:ok, session, :caller}
    else
      false -> {:error, :closed_session}
      {:error, _reason} -> {:error, :invalid_session}
    end
  end

  defp session(%{session: %Jido.Session{} = session}, _context, _now),
    do: {:ok, session, :agent}

  defp session(_state, context, now) do
    agent_id = Map.get(context, :agent_id, Jido.generate_id())
    {:ok, Jido.Session.new(id: "session:#{agent_id}", now: now), :agent}
  end

  defp turn_agent_state(agent_state, :agent), do: Map.delete(agent_state, :session)
  defp turn_agent_state(agent_state, :caller), do: agent_state

  defp request_id(%{signal: %{id: id}}) when is_binary(id), do: id
  defp request_id(_context), do: "request_#{Jido.generate_id()}"
end
