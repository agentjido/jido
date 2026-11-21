defmodule Jido.AI.Reasoning.ReAct.Guards do
  @moduledoc """
  Adds Agent-owned guard Actions to stock ReAct.

  On your Agent module, define `jido_react_guards/0` to return a map with
  optional `:input` and `:output` Action modules. Each Action returns
  `{:ok, %{allowed: boolean, reason: string}}`. The input Action receives
  `%{turn: turn}`. The output Action receives `%{turn: turn, outcome: outcome}`
  for a final answer. Both run after the built-in guard and have the usual
  Action context, including the committed Agent state. Guard Actions must be
  free of effects. Jido saves their targets with the Turn across tool review.

  An output guard withholds provider chunks from `:jido_ai_dispatch`.
  The transport receives progress Signals and a
  `jido.ai.model.stream.approved` Signal after the AgentServer commits an
  approved reply. In a pure Agent command, the approved Signal is an emit
  Directive for the caller to run after it accepts the candidate state.
  To send tool call details to a reviewer, use `:jido_ai_review_dispatch`.
  """

  alias Jido.Agent.Directive

  @doc false
  def capture(%{id: "jido.ai/reasoning/react"}, %{agent_module: module}) when is_atom(module) do
    if function_exported?(module, :jido_react_guards, 0),
      do: validate(module.jido_react_guards()),
      else: {:ok, %{}}
  end

  def capture(_flow, _context), do: {:ok, %{}}

  @doc false
  def output?(turn), do: not is_nil(get_in(turn, [:react_guards, :output]))

  @doc false
  def check({:ok, %{allowed: true} = default}, kind, %{turn: turn} = params, context) do
    case get_in(turn, [:react_guards, kind]) do
      nil ->
        {:ok, default}

      action ->
        case Jido.Exec.run(action, params, context) do
          {:ok, %{allowed: true}} ->
            {:ok, default}

          {:ok, %{allowed: false, reason: reason}} when is_binary(reason) ->
            {:ok, %{default | allowed: false, reason: reason} |> reject(kind)}

          {:error, _reason} = error ->
            error

          _other ->
            {:error, :invalid_react_guard_result}
        end
    end
  end

  def check(default, _kind, _params, _context), do: default

  @doc false
  def release(envelope, %{stream: true} = turn, %{status: :completed} = result, %{jido_ai_dispatch: dispatch} = context)
      when not is_nil(dispatch) do
    if output?(turn) do
      data = Map.take(envelope.response, [:request_id, :run_id, :session_id, :thread_id, :thread_rev])
      data = Map.put(data, :output, result.output)

      with {:ok, signal} <- Jido.Agent.build_signal(context, "jido.ai.model.stream.approved", data) do
        {:ok, envelope, [Directive.emit(signal, dispatch)]}
      end
    else
      {:ok, envelope}
    end
  end

  def release(envelope, _turn, _result, _context), do: {:ok, envelope}

  defp reject(decision, :input), do: %{decision | reason_code: :input}
  defp reject(decision, :output), do: decision

  defp validate(guards) when is_map(guards) and not is_struct(guards) do
    if Enum.all?(guards, fn {kind, target} ->
         kind in [:input, :output] and is_atom(target) and
           match?({:ok, %{kind: :action}}, Jido.Instruction.resolve(target))
       end),
       do: {:ok, guards},
       else: {:error, :invalid_react_guards}
  end

  defp validate(_guards), do: {:error, :invalid_react_guards}
end
