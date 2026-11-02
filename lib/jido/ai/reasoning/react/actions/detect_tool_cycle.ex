defmodule Jido.AI.Reasoning.ReAct.Actions.DetectToolCycle do
  @moduledoc "Detects consecutive identical tool-call batches after tool execution."

  @cycle_warning "The previous tool calls repeated with the same arguments. Do not repeat them again. Use the available results for a final answer, or use a different approach."

  use Jido.Action,
    id: "jido.ai/reasoning/react/actions/detect-tool-cycle",
    vsn: 1,
    name: "jido_ai_react_detect_tool_cycle",
    description: "Detect one repeated ReAct tool-call batch",
    schema: Zoi.object(%{turn: Zoi.any()}),
    output_schema: Zoi.object(%{turn: Zoi.any()})

  @impl Jido.Action
  def run(
        %{turn: %{model_outcome: %{kind: :tool_calls, tool_calls: calls}} = turn},
        _context
      )
      when calls != [] do
    signature = signature(calls)
    repeated = turn.previous_tool_signature == signature

    next_turn = %{
      turn
      | previous_tool_signature: signature,
        repair_instruction: if(repeated, do: @cycle_warning, else: nil),
        tool_cycle_count: turn.tool_cycle_count + if(repeated, do: 1, else: 0)
    }

    {:ok, %{turn: next_turn}}
  end

  def run(%{turn: turn}, _context), do: {:ok, %{turn: turn}}

  @doc false
  @spec signature([map()]) :: String.t()
  def signature(calls) when is_list(calls) do
    calls
    |> Enum.map(fn call ->
      %{
        name: field(call, :name),
        arguments: field(call, :arguments) || %{}
      }
    end)
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
