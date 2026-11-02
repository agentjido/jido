defmodule Jido.AI.Reasoning.ReAct.Actions.ExpandNext do
  @moduledoc "Expands each trusted AI routing decision into its next executable."

  alias Jido.AI.{Telemetry, Toolset}
  alias Jido.AI.Reasoning.ReAct
  alias Jido.AI.Reasoning.ReAct.Actions.{ExecuteTool, RecordToolResults}
  alias Jido.Flow.Ref

  use Jido.Action,
    id: "jido.ai/reasoning/react/actions/expand-next",
    vsn: 1,
    name: "jido_ai_react_expand_next",
    description: "Expand a trusted AI graph routing decision",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{kind: :complete, output: output}, _context), do: {:ok, output}

  def run(%{kind: :model, input: input}, _context),
    do: {:continue, input, ReAct.ModelRound}

  def run(%{kind: :review, input: input}, _context),
    do: {:continue, input, ReAct.ToolReview}

  def run(%{kind: :tools, input: %{turn: turn} = input}, context) do
    with {:ok, calls} <- resolve_calls(turn.tools, turn.model_outcome.tool_calls),
         {:ok, flow} <- build_flow(calls) do
      :ok = Telemetry.record_tool_calls(context, tool_call_index(calls))
      {:continue, input, flow}
    end
  end

  def run(%{kind: :tools}, _context), do: {:error, :invalid_tool_calls}

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

  defp build_flow(calls) do
    Jido.Flow.new(%{
      name: "jido_ai_tool_calls",
      description: "Execute validated tool calls as parallel Actions",
      schema: Zoi.object(%{turn: Zoi.any()}),
      output_schema: Zoi.map(),
      components: [parallel(calls), record(calls), model()],
      output: Ref.result("model")
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

  defp model do
    %{
      kind: :subflow,
      name: "model",
      flow: ReAct.ModelRound,
      params: %{turn: Ref.result("record", :turn)}
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
