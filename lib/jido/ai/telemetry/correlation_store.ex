defmodule Jido.AI.Telemetry.CorrelationStore do
  @moduledoc false

  use GenServer

  @table :jido_ai_telemetry_correlations
  @default_ttl_ms :timer.hours(1)
  @default_sweep_interval_ms :timer.minutes(1)
  @cleanup_event [:jido, :ai, :telemetry, :correlation, :cleanup]

  @type cleanup_callback :: {module(), atom()}
  @type put_option :: {:on_expire, cleanup_callback()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec put(term(), term(), [put_option()]) :: :ok
  def put(key, value, opts \\ []) do
    true = :ets.insert(@table, entry(key, value, opts))
    :ok
  rescue
    ArgumentError -> :ok
  end

  @spec put_new(term(), term(), [put_option()]) :: boolean()
  def put_new(key, value, opts \\ []) do
    :ets.insert_new(@table, entry(key, value, opts))
  rescue
    ArgumentError -> false
  end

  @spec get(term()) :: term() | nil
  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, _generation, value, _inserted_at_ms, _on_expire}] -> value
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @spec take(term()) :: term() | nil
  def take(key) do
    case :ets.take(@table, key) do
      [{^key, _generation, value, _inserted_at_ms, _on_expire}] -> value
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc false
  @spec prune_stale(non_neg_integer()) :: non_neg_integer()
  def prune_stale(ttl_ms) when is_integer(ttl_ms) and ttl_ms >= 0 do
    cutoff_ms = System.monotonic_time(:millisecond) - ttl_ms

    expired =
      :ets.select(@table, [
        {
          {:"$1", :"$2", :"$3", :"$4", :"$5"},
          [{:"=<", :"$4", cutoff_ms}],
          [:"$_"]
        }
      ])

    count = Enum.count(expired, &expire/1)
    emit_cleanup(count)
    count
  rescue
    ArgumentError -> 0
  end

  @doc false
  @spec size() :: non_neg_integer()
  def size do
    case :ets.info(@table, :size) do
      size when is_integer(size) and size >= 0 -> size
      _other -> 0
    end
  rescue
    ArgumentError -> 0
  end

  @impl GenServer
  def init(opts) do
    _table =
      :ets.new(@table, [
        :named_table,
        :public,
        :set,
        keypos: 1,
        read_concurrency: true,
        write_concurrency: true
      ])

    state = %{
      ttl_ms: positive_option(opts, :ttl_ms, configured_ttl_ms()),
      sweep_interval_ms: positive_option(opts, :sweep_interval_ms, configured_sweep_interval_ms())
    }

    schedule_sweep(state.sweep_interval_ms)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:sweep, state) do
    _expired = prune_stale(state.ttl_ms)
    schedule_sweep(state.sweep_interval_ms)
    {:noreply, state}
  end

  defp entry(key, value, opts) do
    {key, make_ref(), value, System.monotonic_time(:millisecond), cleanup_callback(opts)}
  end

  defp cleanup_callback(opts) do
    case Keyword.get(opts, :on_expire) do
      {module, function} when is_atom(module) and is_atom(function) -> {module, function}
      _other -> nil
    end
  end

  defp expire({key, generation, value, _inserted_at_ms, on_expire}) do
    case :ets.select_delete(@table, [
           {{key, generation, :_, :_, :_}, [], [true]}
         ]) do
      1 ->
        run_cleanup(on_expire, key, value)
        true

      0 ->
        false
    end
  end

  defp run_cleanup(nil, _key, _value), do: :ok

  defp run_cleanup({module, function}, key, value) do
    _result = apply(module, function, [key, value])
    :ok
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp emit_cleanup(0), do: :ok

  defp emit_cleanup(count) do
    :telemetry.execute(@cleanup_event, %{expired: count, size: size()}, %{})
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp schedule_sweep(interval_ms), do: Process.send_after(self(), :sweep, interval_ms)

  defp configured_ttl_ms do
    configured_option(:correlation_ttl_ms, @default_ttl_ms)
  end

  defp configured_sweep_interval_ms do
    configured_option(:correlation_sweep_interval_ms, @default_sweep_interval_ms)
  end

  defp configured_option(key, default) do
    :jido
    |> Application.get_env(:ai_telemetry, [])
    |> config_value(key)
    |> positive_integer(default)
  end

  defp positive_option(opts, key, default) do
    opts
    |> Keyword.get(key, default)
    |> positive_integer(default)
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

  defp config_value(config, key) when is_list(config), do: Keyword.get(config, key)
  defp config_value(config, key) when is_map(config), do: Map.get(config, key)
  defp config_value(_config, _key), do: nil
end
