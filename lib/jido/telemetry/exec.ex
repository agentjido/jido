defmodule Jido.Telemetry.Exec do
  @moduledoc """
  Emits semantic telemetry for Jido execution.

  Jido events describe Action attempts and immediate Flow invocations. Runic
  owns telemetry for managed workflow scheduling, runnable dispatch,
  persistence, promises, and rehydration.

  Normal Jido errors complete a span with `outcome: :error`. An `:exception`
  event is reserved for a raise, throw, or exit that escapes the span.
  """

  alias Jido.Error
  alias Jido.Instruction
  alias Runic.Workflow.SingleOutput.Context

  @flow_module Module.concat(["Jido", "Flow"])
  @effect_count_key {__MODULE__, :effect_count}

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
      if kind == :action, do: Process.put(@effect_count_key, 0)
      result = work.()
      stop = Map.merge(metadata, result_metadata(kind, result))
      {result, if(kind == :action, do: put_recorded_effect_count(stop), else: stop)}
    end)
  end

  # A Flow component returns its Action's effects inside the Flow fact, so the
  # node records the count when the Action returns.
  @doc false
  @spec record_effect_count(non_neg_integer()) :: :ok
  def record_effect_count(count) do
    if Process.get(@effect_count_key), do: Process.put(@effect_count_key, count)
    :ok
  end

  defp put_recorded_effect_count(%{effect_count: _count} = stop),
    do: %{stop | effect_count: Process.delete(@effect_count_key)}

  defp put_recorded_effect_count(stop) do
    Process.delete(@effect_count_key)
    stop
  end

  @doc false
  @spec action_metadata(map(), Context.t()) :: map()
  def action_metadata(
        %{instruction: %Instruction{target: action}, flow: flow, name: node_name},
        %Context{} = context
      ) do
    %{
      action: action,
      action_name: action_name(action),
      node_name: node_name,
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
  def result_metadata(_kind, {:ok, _value, effects, :none}) when is_list(effects) do
    %{outcome: :ok, effect_count: length(effects)}
  end

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

  defp error_metadata(kind, error) when kind in [:action, :flow], do: Error.to_map(error)

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

  defp component_kind(%{kind: :call}), do: :step
  defp component_kind(%{kind: kind}), do: kind
  defp component_kind(_metadata), do: nil

  defp invoke_phase(%{kind: :invoke, role: :invoke_decision}), do: :decision
  defp invoke_phase(%{kind: :invoke, role: :invoke_expander}), do: :expander
  defp invoke_phase(%{kind: :invoke, role: :invoke_target}), do: :target
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

  defp flow_name(%{__struct__: module, name: name}) when module == @flow_module, do: name

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
