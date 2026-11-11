defmodule Jido.Exec.ActionBoundary do
  @moduledoc false

  alias Jido.Error
  alias Jido.Exec.{Runtime, Validation}
  alias Jido.Instruction
  alias Jido.Telemetry.Exec, as: Telemetry
  alias Runic.Workflow.SingleOutput.Context

  @type control :: :none | :handoff | :invoke
  @type result ::
          {:ok, term(), [term()], :none}
          | {:handoff, term(), Instruction.target()}
          | {:continue, term(), Instruction.target()}
          | {:error, Exception.t()}

  @doc false
  @spec call(map(), term(), struct(), Context.t(), term()) ::
          {:ok, term(), [term()]} | {:error, Exception.t()}
  def call(call, params, node, context, role) do
    case run(call, params, node, context, role) do
      {:ok, value, effects, :none} -> {:ok, value, effects}
      {:error, error} -> {:error, error}
    end
  end

  @doc false
  @spec run(map(), term(), struct(), Context.t(), term(), control()) :: result()
  def run(call, params, node, context, role, control \\ :none) do
    instruction = Instruction.new!(kind: :action, target: call.target)
    run_instruction(%{instruction | params: params}, node, context, role, control)
  end

  @doc false
  @spec run_instruction(Instruction.t(), struct(), Context.t(), term(), control()) :: result()
  def run_instruction(instruction, node, context, role, control \\ :none) do
    action_context =
      instruction.context
      |> Runtime.caller_context()
      |> Map.merge(context.runtime)

    metadata_node = %{
      instruction: instruction,
      name: node.name,
      flow: %{
        component: component_name(node),
        kind: node_kind(node),
        role: role,
        node_path: telemetry_node_path(node, role)
      }
    }

    Telemetry.span(:action, Telemetry.action_metadata(metadata_node, context), fn ->
      with {:ok, params} <-
             Validation.callback(instruction.target, :validate_params, instruction.params, :input),
           result <- invoke(instruction.target, params, Runtime.user_context(action_context), control),
           result <- validate_output(instruction.target, result) do
        result
      end
    end)
  end

  defp invoke(action, params, context, control) do
    case action
         |> Validation.apply(:run, [params, context], :run)
         |> tap(&record_effect_count/1) do
      {:ok, {:ok, output}} ->
        {:ok, output, [], :none}

      {:ok, {:ok, output, effects}} when is_list(effects) ->
        if List.improper?(effects), do: invalid_effects(action, effects), else: {:ok, output, effects, :none}

      {:ok, {:ok, _output, effects}} ->
        invalid_effects(action, effects)

      {:ok, {:error, reason}} ->
        {:error, normalize_error(action, reason)}

      {:ok, {:error, reason, _effects}} ->
        {:error, normalize_error(action, reason)}

      {:ok, {:handoff, input, target}} when control in [:handoff, :invoke] ->
        {:handoff, input, target}

      {:ok, {:handoff, _input, _target}} ->
        {:error,
         Error.execution_error("only a Handoff selector can hand off", %{
           action: action,
           phase: :run,
           reason: :unsupported_handoff
         })}

      {:ok, {:continue, input, target}} ->
        continue_result(control, action, input, target)

      {:ok, other} ->
        {:error,
         Error.execution_error("Action returned an invalid value", %{
           action: action,
           phase: :run,
           return: other,
           reason: :invalid_return
         })}

      {:error, error} ->
        {:error, error}
    end
  end

  defp validate_output(action, {:ok, value, effects, :none}) do
    with {:ok, value} <- Validation.callback(action, :validate_output, value, :output) do
      {:ok, value, effects, :none}
    end
  end

  defp validate_output(_action, control), do: control

  defp continue_result(:invoke, _action, input, target), do: {:continue, input, target}

  defp continue_result(_control, action, input, target) do
    continuation = {:continue, input, target}

    {:error,
     Error.execution_error("Action continuations are not supported by Runic execution", %{
       action: action,
       phase: :run,
       return: continuation,
       reason: :unsupported_continuation
     })}
  end

  defp telemetry_node_path(node, {:parallel, name}), do: node.node_path ++ [name]
  defp telemetry_node_path(node, _role), do: node.node_path

  defp node_kind(%{definition: %{kind: kind}}), do: kind
  defp node_kind(%Jido.Exec.Node.Action{}), do: :call

  defp component_name(%{name: name}), do: name

  defp record_effect_count({:ok, {:ok, _output, effects}}) when is_list(effects) do
    unless List.improper?(effects), do: Telemetry.record_effect_count(length(effects))
  end

  defp record_effect_count(_result), do: Telemetry.record_effect_count(0)

  defp normalize_error(_action, error) when is_exception(error), do: error

  defp normalize_error(action, reason) do
    Error.execution_error(error_message(reason), %{action: action, phase: :run, reason: reason})
  end

  defp invalid_effects(action, effects) do
    {:error,
     Error.execution_error("Action returned an invalid effects list", %{
       action: action,
       phase: :run,
       effects: effects,
       reason: :invalid_effects
     })}
  end

  defp error_message(message) when is_binary(message), do: message
  defp error_message(message) when is_atom(message), do: Atom.to_string(message)
  defp error_message(message), do: inspect(message)
end
