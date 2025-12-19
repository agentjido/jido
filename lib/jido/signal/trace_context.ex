defmodule Jido.Signal.TraceContext do
  @moduledoc """
  Lightweight trace context management using the process dictionary.

  Provides simple trace context storage and retrieval for correlating signals
  within a process without requiring external dependencies or complex state management.

  ## Usage

      # Set trace context
      Jido.Signal.TraceContext.set(%{trace_id: "abc123", span_id: "def456"})

      # Retrieve current context
      context = Jido.Signal.TraceContext.current()

      # Clear context
      Jido.Signal.TraceContext.clear()

      # Ensure context from signal
      signal = %Jido.Signal{extensions: %{"correlation" => trace_data}}
      Jido.Signal.TraceContext.ensure_set_from_state(%{current_signal: signal})

  ## See Also
  * `Jido.Signal.Ext.Trace` - The trace extension for signals
  * `Jido.Signal` - Main signal struct
  """

  alias Jido.Signal

  @trace_context_key :jido_trace_context

  @doc """
  Gets the current trace context from the process dictionary.

  Returns the trace context map or `nil` if no context is set.

  ## Examples

      iex> Jido.Signal.TraceContext.current()
      nil

      iex> Jido.Signal.TraceContext.set(%{trace_id: "abc123"})
      iex> Jido.Signal.TraceContext.current()
      %{trace_id: "abc123"}
  """
  @spec current() :: map() | nil
  def current do
    Process.get(@trace_context_key)
  end

  @doc """
  Sets the trace context in the process dictionary.

  Accepts a map containing trace context data such as `trace_id`, `span_id`,
  `parent_span_id`, and `causation_id`.

  ## Parameters
  * `context` - Map containing trace context data

  ## Examples

      iex> Jido.Signal.TraceContext.set(%{trace_id: "abc123", span_id: "def456"})
      :ok

      iex> Jido.Signal.TraceContext.current()
      %{trace_id: "abc123", span_id: "def456"}
  """
  @spec set(map()) :: :ok
  def set(context) when is_map(context) do
    Process.put(@trace_context_key, context)
    :ok
  end

  @doc """
  Clears the trace context from the process dictionary.

  ## Examples

      iex> Jido.Signal.TraceContext.set(%{trace_id: "abc123"})
      iex> Jido.Signal.TraceContext.clear()
      :ok

      iex> Jido.Signal.TraceContext.current()
      nil
  """
  @spec clear() :: :ok
  def clear do
    Process.delete(@trace_context_key)
    :ok
  end

  @doc """
  Ensures trace context is set from the current_signal in the given state.

  Extracts trace context from the `current_signal` field if it contains
  trace extension data and sets it as the process trace context.

  ## Parameters
  * `state` - Map or struct containing a `current_signal` field

  ## Returns
  * `:ok` if context was set or no signal present
  * `:error` if signal exists but has no trace data

  ## Examples

      signal = %Jido.Signal{
        extensions: %{"correlation" => %{trace_id: "abc123", span_id: "def456"}}
      }
      state = %{current_signal: signal}

      iex> Jido.Signal.TraceContext.ensure_set_from_state(state)
      :ok

      iex> Jido.Signal.TraceContext.current()
      %{trace_id: "abc123", span_id: "def456"}
  """
  @spec ensure_set_from_state(map()) :: :ok | :error
  def ensure_set_from_state(%{current_signal: %Signal{} = signal}) do
    case get_in(signal.extensions, ["correlation"]) do
      nil ->
        :error

      trace_data when is_map(trace_data) ->
        set(trace_data)
        :ok

      _ ->
        :error
    end
  end

  def ensure_set_from_state(%{current_signal: nil}), do: :ok
  def ensure_set_from_state(_state), do: :ok
end
