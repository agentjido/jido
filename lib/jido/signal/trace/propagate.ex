defmodule Jido.Signal.Trace.Propagate do
  @moduledoc """
  Provides trace context propagation for Jido signals.

  This module enriches signal attributes with trace context information,
  enabling distributed tracing across signal processing workflows. It works
  with the existing Trace extension from the jido_signal project to maintain
  correlation between related signals.

  The propagation logic handles:
  * Extracting trace context from the current process or signal
  * Generating new span IDs for child signals
  * Setting causation relationships between signals
  * Creating root trace contexts when none exist

  ## Usage

      # Inject trace context into signal attributes
      attrs = %{"type" => "user.created", "subject" => "user123"}
      state = %{current_signal: some_signal}
      enriched_attrs = Jido.Signal.Trace.Propagate.inject_trace_context(attrs, state)

  ## See Also
  * `Jido.Signal.TraceContext` - Process-local trace context management
  * `Jido.Signal.Ext.Trace` - Signal trace extension from jido_signal
  * `Jido.Signal.ID` - UUID7-based ID generation
  """

  alias Jido.Signal.TraceContext
  alias Jido.Signal.ID

  @doc """
  Enriches signal attributes with trace context information.

  Takes signal attributes and server state, then returns updated attributes
  with the trace extension applied. The function handles three scenarios:

  1. **Continuing trace**: Uses existing trace context from process or current signal
  2. **Child signal**: Creates new span ID with parent relationship
  3. **Root signal**: Generates new trace context when none exists

  ## Parameters
  * `attrs` - Map of signal attributes to be enriched
  * `state` - Server state containing current signal and other context

  ## Returns
  Updated attributes map with trace extension data applied

  ## Examples

      # With existing trace context
      attrs = %{"type" => "user.created"}
      state = %{current_signal: %Jido.Signal{id: "parent-123"}}
      
      result = inject_trace_context(attrs, state)
      # => %{
      #      "type" => "user.created",
      #      # ... plus trace extension attributes
      #    }

      # Root signal (no existing trace)
      attrs = %{"type" => "workflow.started"}
      state = %{current_signal: nil}
      
      result = inject_trace_context(attrs, state)
      # => %{
      #      "type" => "workflow.started",
      #      # ... plus trace extension attributes
      #    }
  """
  @spec inject_trace_context(map(), map()) :: map()
  def inject_trace_context(attrs, state) when is_map(attrs) and is_map(state) do
    trace_data = build_trace_data(state)
    apply_trace_extension(attrs, trace_data)
  end

  # Private helper to build trace data based on current context
  @spec build_trace_data(map()) :: map()
  defp build_trace_data(state) do
    current_context = TraceContext.current()
    current_signal = Map.get(state, :current_signal)

    case {current_context, current_signal} do
      # Case 1: Have process trace context - continue with new span
      {%{} = context, _} when map_size(context) > 0 ->
        build_child_trace_data(context, current_signal)

      # Case 2: No process context but have current signal with trace - extract and continue
      {_, %{extensions: %{"correlation" => trace_ext}} = signal} when is_map(trace_ext) ->
        build_child_trace_data(trace_ext, signal)

      # Case 3: No trace context - create root trace
      _ ->
        build_root_trace_data()
    end
  end

  # Build trace data for a child signal (continuing existing trace)
  @spec build_child_trace_data(map(), map() | nil) :: map()
  defp build_child_trace_data(parent_trace, current_signal) do
    new_span_id = ID.generate!()

    %{
      trace_id: Map.get(parent_trace, :trace_id) || Map.get(parent_trace, "trace_id"),
      span_id: new_span_id,
      parent_span_id: Map.get(parent_trace, :span_id) || Map.get(parent_trace, "span_id"),
      causation_id: get_causation_id(current_signal)
    }
    |> filter_nil_values()
  end

  # Build trace data for a root signal (new trace)
  @spec build_root_trace_data() :: map()
  defp build_root_trace_data do
    new_id = ID.generate!()

    %{
      trace_id: new_id,
      span_id: new_id
    }
  end

  # Extract causation ID from current signal
  @spec get_causation_id(map() | nil) :: String.t() | nil
  defp get_causation_id(%{id: id}) when is_binary(id), do: id
  defp get_causation_id(_), do: nil

  # Filter out nil values from the trace data map
  @spec filter_nil_values(map()) :: map()
  defp filter_nil_values(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.into(%{})
  end

  # Apply trace extension to signal attributes by adding CloudEvents attributes
  @spec apply_trace_extension(map(), map()) :: map()
  defp apply_trace_extension(attrs, trace_data) when map_size(trace_data) > 0 do
    trace_attrs = build_trace_attrs(trace_data)
    Map.merge(attrs, trace_attrs)
  end

  defp apply_trace_extension(attrs, _empty_trace_data), do: attrs

  # Build CloudEvents attributes from trace data (matching Trace extension format)
  @spec build_trace_attrs(map()) :: map()
  defp build_trace_attrs(%{trace_id: trace_id, span_id: span_id} = data) do
    %{
      "trace_id" => trace_id,
      "span_id" => span_id
    }
    |> maybe_put_trace_attr("parent_span_id", data[:parent_span_id])
    |> maybe_put_trace_attr("causation_id", data[:causation_id])
  end

  defp build_trace_attrs(_invalid_data), do: %{}

  # Helper to conditionally add trace attributes
  @spec maybe_put_trace_attr(map(), String.t(), String.t() | nil) :: map()
  defp maybe_put_trace_attr(attrs, _key, nil), do: attrs
  defp maybe_put_trace_attr(attrs, key, value), do: Map.put(attrs, key, value)
end
