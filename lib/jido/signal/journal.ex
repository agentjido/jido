defmodule Jido.Signal.Journal do
  @moduledoc """
  The Signal Journal tracks and manages signals between agents, maintaining causality
  and conversation relationships. It provides a directed graph of signals that captures
  temporal ordering and causal relationships.
  """
  use TypedStruct
  alias Jido.Signal

  typedstruct do
    @typedoc "The journal maintains the graph of signals and their relationships"
    field(:adapter, module(), enforce: true)
    field(:adapter_pid, pid())
  end

  @type query_opts :: [
          type: String.t() | nil,
          source: String.t() | nil,
          after: DateTime.t() | nil,
          before: DateTime.t() | nil
        ]

  @doc """
  Creates a new journal with the specified persistence adapter.
  """
  @spec new(module()) :: t()
  def new(adapter \\ Jido.Signal.Journal.Adapters.InMemory) do
    case adapter.init() do
      {:ok, pid} when adapter == Jido.Signal.Journal.Adapters.ETS ->
        %__MODULE__{adapter: adapter, adapter_pid: pid}

      :ok ->
        %__MODULE__{adapter: adapter}

      error ->
        error
    end
  end

  @doc """
  Records a new signal in the journal.

  ## Parameters
    * journal - The current journal state
    * signal - The signal to record
    * cause_id - Optional ID of the signal that caused this one

  Returns `{:ok, journal}` or `{:error, reason}`
  """
  @spec record(t(), Signal.t(), String.t() | nil) :: {:ok, t()} | {:error, atom()}
  def record(journal, %Signal{} = signal, cause_id \\ nil) do
    with :ok <- validate_causality(journal, signal, cause_id),
         :ok <- put_signal(journal, signal),
         :ok <- add_to_conversation(journal, signal),
         :ok <- maybe_add_causality(journal, signal, cause_id) do
      {:ok, journal}
    end
  end

  @doc """
  Gets all signals in a conversation.

  ## Parameters
    * journal - The current journal state
    * conversation_id - The ID of the conversation to fetch

  Returns a list of signals in chronological order
  """
  @spec get_conversation(t(), String.t()) :: [Signal.t()]
  def get_conversation(%__MODULE__{} = journal, conversation_id) do
    case call_adapter(journal, :get_conversation, [conversation_id]) do
      {:ok, signal_ids} ->
        signal_ids
        |> MapSet.to_list()
        |> Task.async_stream(fn id ->
          case call_adapter(journal, :get_signal, [id]) do
            {:ok, signal} -> signal
            _ -> nil
          end
        end)
        |> Stream.map(fn {:ok, signal} -> signal end)
        |> Stream.reject(&is_nil/1)
        |> Enum.sort_by(& &1.time, &sort_time_compare/2)

      _ ->
        []
    end
  end

  @doc """
  Gets all effects (signals caused by) of a given signal.

  ## Parameters
    * journal - The current journal state
    * signal_id - The ID of the signal to get effects for

  Returns a list of signals in chronological order
  """
  @spec get_effects(t(), String.t()) :: [Signal.t()]
  def get_effects(%__MODULE__{} = journal, signal_id) do
    case call_adapter(journal, :get_effects, [signal_id]) do
      {:ok, effect_ids} ->
        effect_ids
        |> MapSet.to_list()
        |> Task.async_stream(fn id ->
          case call_adapter(journal, :get_signal, [id]) do
            {:ok, signal} -> signal
            _ -> nil
          end
        end)
        |> Stream.map(fn {:ok, signal} -> signal end)
        |> Stream.reject(&is_nil/1)
        |> Enum.sort_by(& &1.time, &sort_time_compare/2)

      _ ->
        []
    end
  end

  @doc """
  Gets the cause of a given signal.

  ## Parameters
    * journal - The current journal state
    * signal_id - The ID of the signal to get the cause for

  Returns the causing signal or nil if none exists
  """
  @spec get_cause(t(), String.t()) :: Signal.t() | nil
  def get_cause(%__MODULE__{} = journal, signal_id) do
    with {:ok, cause_id} <- call_adapter(journal, :get_cause, [signal_id]),
         {:ok, signal} <- call_adapter(journal, :get_signal, [cause_id]) do
      signal
    else
      _ -> nil
    end
  end

  @doc """
  Traces the complete causal chain starting from a signal.

  ## Parameters
    * journal - The current journal state
    * signal_id - The ID of the signal to trace from
    * direction - :forward for effects chain, :backward for causes chain

  Returns a list of signals in causal order
  """
  @spec trace_chain(t(), String.t(), :forward | :backward) :: [Signal.t()]
  def trace_chain(journal, signal_id, direction \\ :forward) do
    case call_adapter(journal, :get_signal, [signal_id]) do
      {:ok, signal} ->
        do_trace_chain(journal, [signal], direction, MapSet.new([signal_id]))

      _ ->
        []
    end
  end

  @doc """
  Queries signals based on criteria.

  ## Options
    * type - Filter by signal type
    * source - Filter by signal source
    * after - Filter signals after this time
    * before - Filter signals before this time

  Returns a list of signals matching all criteria, in chronological order
  """
  @spec query(t(), query_opts()) :: [Signal.t()]
  def query(%__MODULE__{} = journal, opts \\ []) do
    # Note: This is inefficient for large datasets as it loads all signals
    # A real implementation would push filtering down to the persistence layer
    get_all_signals(journal)
    |> Enum.filter(&matches_criteria?(&1, opts))
    |> Enum.sort_by(& &1.time, &sort_time_compare/2)
  end

  # Private helpers

  defp validate_causality(_journal, _signal, nil), do: :ok

  defp validate_causality(journal, signal, cause_id) do
    case call_adapter(journal, :get_signal, [cause_id]) do
      {:ok, cause} ->
        cond do
          # Would create a cycle
          would_create_cycle?(journal, signal.id, cause_id) ->
            {:error, :causality_cycle}

          # Cause is chronologically after the effect
          time_compare(signal.time, cause.time) == :lt ->
            {:error, :invalid_temporal_order}

          true ->
            :ok
        end

      {:error, :not_found} ->
        {:error, :cause_not_found}

      error ->
        error
    end
  end

  defp would_create_cycle?(journal, effect_id, cause_id) do
    # Check if the effect is already in the cause's chain
    cause_chain = trace_chain(journal, cause_id, :backward)
    Enum.any?(cause_chain, &(&1.id == effect_id))
  end

  defp add_to_conversation(journal, signal) do
    conversation_id = signal.subject || "default"
    call_adapter(journal, :put_conversation, [conversation_id, signal.id])
  end

  defp maybe_add_causality(_journal, _signal, nil), do: :ok

  defp maybe_add_causality(journal, signal, cause_id) do
    call_adapter(journal, :put_cause, [cause_id, signal.id])
  end

  defp put_signal(journal, signal) do
    call_adapter(journal, :put_signal, [signal])
  end

  defp get_all_signals(%__MODULE__{adapter: Jido.Signal.Journal.Adapters.ETS} = journal) do
    call_adapter(journal, :get_all_signals, [])
  end

  defp get_all_signals(%__MODULE__{adapter: adapter}) do
    adapter.get_all_signals()
  end

  defp call_adapter(
         %__MODULE__{adapter: Jido.Signal.Journal.Adapters.ETS, adapter_pid: pid} = _journal,
         function,
         args
       ) do
    apply(Jido.Signal.Journal.Adapters.ETS, function, args ++ [pid])
  end

  defp call_adapter(%__MODULE__{adapter: adapter} = _journal, function, args) do
    apply(adapter, function, args)
  end

  defp do_trace_chain(_journal, chain, _direction, _visited) when length(chain) > 100 do
    # Prevent infinite recursion by limiting chain length
    chain
  end

  defp do_trace_chain(journal, chain, direction, visited) do
    current = List.last(chain)

    next_signals =
      case direction do
        :forward -> get_effects(journal, current.id)
        :backward -> [get_cause(journal, current.id)]
      end
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&MapSet.member?(visited, &1.id))

    case next_signals do
      [] ->
        chain

      signals ->
        new_visited = Enum.reduce(signals, visited, &MapSet.put(&2, &1.id))

        Enum.reduce(signals, chain, fn signal, acc ->
          do_trace_chain(journal, acc ++ [signal], direction, new_visited)
        end)
    end
  end

  defp matches_criteria?(signal, opts) do
    Enum.all?([
      matches_type?(signal, opts[:type]),
      matches_source?(signal, opts[:source]),
      matches_time_range?(signal, opts[:after], opts[:before])
    ])
  end

  defp matches_type?(_signal, nil), do: true
  defp matches_type?(signal, type), do: signal.type == type

  defp matches_source?(_signal, nil), do: true
  defp matches_source?(signal, source), do: signal.source == source

  defp matches_time_range?(signal, after_time, before_time) do
    matches_after?(signal, after_time) and matches_before?(signal, before_time)
  end

  defp matches_after?(_signal, nil), do: true
  defp matches_after?(signal, after_time), do: time_compare(signal.time, after_time) in [:gt, :eq]

  defp matches_before?(_signal, nil), do: true
  defp matches_before?(signal, before_time), do: time_compare(signal.time, before_time) == :lt

  # Time comparison helpers
  defp time_compare(time1, time2) when is_binary(time1) and is_binary(time2) do
    {:ok, dt1, _} = DateTime.from_iso8601(time1)
    {:ok, dt2, _} = DateTime.from_iso8601(time2)
    DateTime.compare(dt1, dt2)
  end

  defp time_compare(time1, %DateTime{} = time2) when is_binary(time1) do
    {:ok, dt1, _} = DateTime.from_iso8601(time1)
    DateTime.compare(dt1, time2)
  end

  defp time_compare(%DateTime{} = time1, time2) when is_binary(time2) do
    {:ok, dt2, _} = DateTime.from_iso8601(time2)
    DateTime.compare(time1, dt2)
  end

  defp time_compare(%DateTime{} = time1, %DateTime{} = time2) do
    DateTime.compare(time1, time2)
  end

  # Sorting comparison function
  defp sort_time_compare(time1, time2) do
    case time_compare(time1, time2) do
      :lt -> true
      :eq -> true
      :gt -> false
    end
  end
end
