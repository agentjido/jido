defmodule Jido.AI.Reasoning.ReAct.ToolRound do
  @moduledoc false

  alias Jido.AI.Reasoning.ReAct.Actions.{ExecuteTool, RecordToolResults}
  alias Jido.AI.Toolset
  alias Jido.Flow.Ref
  alias Jido.Joi
  alias Jido.Telemetry.AI, as: Telemetry

  @doc false
  @spec run(map(), map()) :: {:ok, map(), [term()]} | {:error, term()}
  def run(turn, context) when is_map(turn) and is_map(context) do
    with {:ok, flow} <- build(turn, context) do
      max_concurrency = Jido.Exec.Runtime.max_concurrency()

      case Jido.Exec.run(flow, %{turn: turn}, context, max_concurrency: max_concurrency) do
        {:ok, %{turn: next_turn}} -> {:ok, next_turn, []}
        {:ok, %{turn: next_turn}, effects} -> {:ok, next_turn, effects}
        {:error, _error} = error -> error
      end
    end
  end

  @doc false
  @spec build(map(), map(), keyword()) :: {:ok, Jido.Flow.t()} | {:error, term()}
  def build(turn, context, opts \\ [])
      when is_map(turn) and is_map(context) and is_list(opts) do
    with {:ok, calls} <- resolve_calls(turn.tools, turn.model_outcome.tool_calls),
         :ok <- Telemetry.record_tool_calls(context, tool_call_index(calls)) do
      build_flow(calls, Keyword.get(opts, :continuation))
    end
  end

  defp resolve_calls(tools, calls) when is_list(calls) and calls != [] do
    calls
    |> Enum.reduce_while({:ok, []}, fn call, {:ok, resolved} ->
      case Toolset.resolve_call(tools, call) do
        {:ok, value} -> {:cont, {:ok, [value | resolved]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, resolved} -> {:ok, Enum.reverse(resolved)}
      error -> error
    end
  end

  defp resolve_calls(_tools, calls), do: {:error, {:invalid_tool_calls, calls}}

  defp build_flow(calls, continuation) do
    components = [parallel(calls), record(calls)]

    {schema, components, output} =
      if continuation do
        {
          Joi.object(%{turn: Joi.any(), routes: Joi.map()}),
          components ++ [continuation(continuation)],
          Ref.result("model")
        }
      else
        {Joi.object(%{turn: Joi.any()}), components, Ref.result("record")}
      end

    Jido.Flow.new(%{
      name: "jido_ai_tool_round",
      description: "Execute one validated ReAct tool round",
      schema: schema,
      output_schema: Joi.map(),
      components: components,
      output: output
    })
  end

  defp parallel(calls) do
    %{
      kind: :parallel,
      name: "tools",
      on_error: :collect_errors,
      actions:
        calls
        |> Enum.with_index()
        |> Enum.map(fn {call, index} ->
          %{
            name: action_name(index),
            action: ExecuteTool,
            params: %{call: Map.take(call, [:id, :name, :arguments, :params, :executor, :tool])}
          }
        end)
    }
  end

  defp record(calls) do
    %{
      kind: :step,
      name: "record",
      action: RecordToolResults,
      params: %{
        turn: Ref.input(:turn),
        results: result_refs(calls)
      }
    }
  end

  defp continuation(target) do
    %{
      kind: :subflow,
      name: "model",
      flow: target,
      params: %{turn: Ref.result("record", :turn), routes: Ref.input(:routes)}
    }
  end

  defp result_refs(calls) do
    calls
    |> Enum.with_index()
    |> Enum.map(fn {call, index} ->
      %{id: call.id, name: call.name, outcome: Ref.result("tools", [index])}
    end)
  end

  defp tool_call_index(calls) do
    calls
    |> Enum.with_index()
    |> Map.new(fn {call, index} ->
      telemetry =
        call
        |> Map.take([:id, :name, :description])
        |> Map.put(:action, tool_action(call.executor))

      {action_name(index), telemetry}
    end)
  end

  defp tool_action(%{kind: :action, target: action}), do: action
  defp tool_action(%{kind: :flow, target: flow}), do: flow
  defp tool_action(%{kind: :source, module: module}), do: module

  defp action_name(index), do: "tool_#{index}"
end
