defmodule Jido.AI.Reasoning.ReAct.Actions.ExecuteTool do
  @moduledoc "Executes one resolved tool and returns a timed observation envelope."

  alias Jido.AI.{ToolResult, ToolSource}

  use Jido.Action,
    id: "jido.ai/reasoning/react/actions/execute-tool",
    vsn: 1,
    name: "jido_ai_react_execute_tool",
    description: "Execute one static or dynamic tool through the Agent graph",
    schema: Zoi.object(%{call: Zoi.map()}),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{call: call}, context) do
    started_at_ms = System.system_time(:millisecond)
    started_at = System.monotonic_time(:millisecond)

    {outcome, effects} = execute(call, context)
    outcome = ToolResult.portable_outcome(outcome)
    completed_at_ms = System.system_time(:millisecond)

    observation = %{
      version: 1,
      call: Map.take(call, [:id, :name, :arguments]),
      tool: call.tool,
      outcome: outcome,
      started_at_ms: started_at_ms,
      completed_at_ms: completed_at_ms,
      duration_ms: max(System.monotonic_time(:millisecond) - started_at, 0),
      effects_count: length(effects)
    }

    if effects == [], do: {:ok, observation}, else: {:ok, observation, effects}
  end

  defp execute(%{executor: %{kind: :action, target: action}, params: params}, context) do
    action
    |> Jido.Exec.call_action(params, context)
    |> normalize_result()
  end

  defp execute(%{executor: %{kind: :flow, target: flow}, params: params}, context) do
    flow
    |> Jido.Exec.run(params, context)
    |> normalize_result()
  end

  defp execute(%{executor: %{kind: :source} = source, id: id, name: name, params: params}, context) do
    source
    |> ToolSource.run(%{id: id, name: name, arguments: params}, context)
    |> normalize_result()
  end

  defp normalize_result({:ok, %Jido.Action.Output{kind: :preserve, value: value}}),
    do: normalize_result({:ok, value})

  defp normalize_result({:ok, %Jido.Action.Output{kind: :preserve, value: value}, effects}),
    do: normalize_result({:ok, value, effects})

  defp normalize_result({:ok, value}), do: {%{status: :ok, value: value}, []}

  defp normalize_result({:ok, value, effects}) when is_list(effects) do
    if List.improper?(effects),
      do: {%{status: :error, error: portable_error(:invalid_tool_effects)}, []},
      else: {%{status: :ok, value: value}, effects}
  end

  defp normalize_result({:error, %ReqLLM.ToolResult{} = error}),
    do: {%{status: :error, error: error}, []}

  defp normalize_result({:error, error}),
    do: {%{status: :error, error: portable_error(error)}, []}

  defp portable_error(error) do
    error
    |> Jido.Flow.Error.to_map()
    |> Map.take([:type, :message, :retryable?])
  end
end
