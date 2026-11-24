defmodule Jido.AI.Reasoning.ReAct.Actions.ExecuteTool do
  alias Jido.Joi
  @moduledoc "Executes one resolved tool and returns a timed observation envelope."

  alias Jido.AI.{ToolResult, ToolSource}

  use Jido.Action,
    id: "jido.ai/reasoning/react/actions/execute-tool",
    vsn: 1,
    name: "jido_ai_react_execute_tool",
    description: "Execute one static or dynamic tool through the Agent graph",
    schema: Joi.object(%{call: Joi.map()}),
    output_schema: Joi.map()

  @impl Jido.Action
  def run(%{call: call} = params, context) do
    recorder = Jido.Exec.Runtime.tool_recorder()
    execute = fn -> observe(call, context) end

    result =
      case params do
        %{slot: slot, max_output_bytes: max_bytes} when is_function(recorder, 3) ->
          identity = Map.take(call, [:name, :arguments, :params, :executor, :tool])
          recorder.(slot, {identity, max_bytes}, fn -> normalize_observation(execute.(), max_bytes) end)

        _ ->
          {:ok, execute.()}
      end

    case result do
      {:ok, {observation, effects}} ->
        # A replay can receive a new provider ID for the same validated call.
        observation = put_in(observation.call.id, call.id)
        if effects == [], do: {:ok, observation}, else: {:ok, observation, effects}

      {:error, reason} ->
        {:error,
         Jido.Error.execution_error("Could not confirm the tool result", %{
           reason: :jido_tool_result_store,
           storage_reason: reason
         })}
    end
  end

  defp normalize_observation({observation, effects}, max_bytes) do
    {outcome, observation} = Map.pop!(observation, :outcome)
    normalized = outcome |> ToolResult.normalize(max_bytes) |> Map.delete(:value)
    {Map.put(observation, :normalized, normalized), effects}
  end

  defp observe(call, context) do
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

    {observation, effects}
  end

  defp execute(%{executor: %{kind: :action, target: action}, params: params}, context) do
    action
    |> Jido.Exec.run(params, context)
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
    |> Jido.Error.to_map()
    |> Map.take([:type, :message, :retryable?])
  end
end
