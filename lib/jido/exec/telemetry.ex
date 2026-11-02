defmodule Jido.Exec.Telemetry do
  @moduledoc """
  Emits semantic telemetry for Jido execution.

  Jido events describe Action attempts and immediate Flow invocations. Runic
  owns telemetry for managed workflow scheduling, runnable dispatch,
  persistence, promises, and rehydration.

  Normal Jido errors complete a span with `outcome: :error`. An `:exception`
  event is reserved for a raise, throw, or exit that escapes the span.
  """

  alias Jido.Action.Error, as: ActionError
  alias Jido.Exec.Node.Action
  alias Jido.Flow
  alias Jido.Flow.Error, as: FlowError
  alias Jido.Instruction
  alias Runic.Workflow.SingleOutput.Context

  @type kind :: :action | :flow

  @event_names [
    [:jido, :action, :start],
    [:jido, :action, :stop],
    [:jido, :action, :exception],
    [:jido, :flow, :start],
    [:jido, :flow, :stop],
    [:jido, :flow, :exception]
  ]

  @doc "Returns all telemetry event names emitted by Jido Exec."
  @spec event_names() :: [[atom()]]
  def event_names, do: @event_names

  @doc false
  @spec span(kind(), map(), (-> result)) :: result when result: term()
  def span(kind, metadata, work)
      when kind in [:action, :flow] and is_map(metadata) and is_function(work, 0) do
    :telemetry.span([:jido, kind], metadata, fn ->
      result = work.()
      {result, Map.merge(metadata, result_metadata(kind, result))}
    end)
  end

  @doc false
  @spec action_metadata(Action.t(), Context.t()) :: map()
  def action_metadata(
        %Action{instruction: %Instruction{target: action}, flow: flow} = node,
        %Context{} = context
      ) do
    %{
      action: action,
      action_name: action_name(action),
      node_name: node.name,
      runnable_id: context.runnable_id,
      activation_id: context.activation_id,
      attempt_id: context.attempt_id,
      attempt: context.attempt_number
    }
    |> Map.merge(flow_component_metadata(flow))
    |> Map.merge(runtime_correlation(context.runtime))
  end

  @doc false
  @spec flow_metadata(Instruction.t()) :: map()
  def flow_metadata(%Instruction{kind: :flow, target: target}) do
    %{kind: :flow, flow: flow_name(target)}
    |> maybe_put(:target, flow_module(target))
  end

  @doc false
  @spec result_metadata(kind(), term()) :: map()
  def result_metadata(_kind, {:ok, _value}), do: %{outcome: :ok, effect_count: 0}

  def result_metadata(_kind, {:ok, _value, effects}) when is_list(effects) do
    %{outcome: :ok, effect_count: length(effects)}
  end

  def result_metadata(:flow, {:handoff, _instruction, effects}),
    do: %{outcome: :handoff, effect_count: length(effects)}

  def result_metadata(kind, {:error, error}) do
    error = error_metadata(kind, error)

    %{
      outcome: :error,
      error_type: error.type,
      retryable?: error.retryable?
    }
  end

  def result_metadata(_kind, _result), do: %{outcome: :unknown}

  defp error_metadata(:action, error), do: ActionError.to_map(error)
  defp error_metadata(:flow, error), do: FlowError.to_map(error)

  defp flow_component_metadata(nil), do: %{}

  defp flow_component_metadata(metadata) when is_map(metadata) do
    component = Map.get(metadata, :component)

    %{}
    |> maybe_put(:component, component)
    |> maybe_put(:node_path, Map.get(metadata, :node_path, default_node_path(component)))
    |> maybe_put(:component_kind, component_kind(metadata))
    |> maybe_put(:invoke_phase, invoke_phase(metadata))
  end

  defp flow_component_metadata(_metadata), do: %{}

  defp component_kind(%{mode: {:map, _on_error}}), do: :map

  defp component_kind(%{mode: {:parallel, _on_error, _index, _name}}),
    do: :parallel

  defp component_kind(%{mode: {:loop, %{kind: kind}}}) when kind in [:reduce, :iterate], do: kind
  defp component_kind(%{mode: {:invoke, _phase}}), do: :invoke
  defp component_kind(%{mode: :handoff}), do: :handoff
  defp component_kind(%{mode: :choice}), do: :choice
  defp component_kind(%{component: component}) when not is_nil(component), do: :step
  defp component_kind(_metadata), do: nil

  defp invoke_phase(%{mode: {:invoke, phase}}), do: phase
  defp invoke_phase(_metadata), do: nil

  defp default_node_path(nil), do: nil
  defp default_node_path(component), do: [component]

  defp runtime_correlation(runtime) when is_map(runtime) do
    trace = Map.get(runtime, :trace_context, %{})

    runtime
    |> Map.take([:agent_id, :agent_module, :turn_id])
    |> Map.merge(Map.take(trace, [:trace_id, :span_id, :parent_span_id]))
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp runtime_correlation(_runtime), do: %{}

  defp action_name(action) do
    if function_exported?(action, :name, 0), do: action.name(), else: Atom.to_string(action)
  rescue
    _exception -> Atom.to_string(action)
  end

  defp flow_name(%Flow{name: name}), do: name

  defp flow_name(module) when is_atom(module) do
    if function_exported?(module, :name, 0), do: module.name(), else: Atom.to_string(module)
  rescue
    _exception -> Atom.to_string(module)
  end

  defp flow_name(target), do: inspect(target)

  defp flow_module(module) when is_atom(module), do: module
  defp flow_module(_target), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
