defmodule Jido.Persistence.Store do
  @moduledoc """
  Shared byte storage boundary for Jido runtimes.

  Call `open/1` before use. A store holds binary keys and values. `read/2`
  returns the bytes and a condition for the next atomic write. The condition
  is either the exact bytes or an opaque adapter token. `:not_found` is the
  condition for a missing key.

  `compare_and_swap/4` never implements a write with a separate read and put.
  A conflict means that no write occurred. A rejection means that the adapter
  finished a documented check before a write started. Any other failed write
  has an indeterminate outcome. Do not retry it without a new authoritative
  read and domain-level recovery decision.

  This module does not define keys, record formats, revisions, tombstones, or
  the runtime response to a failed write. The Agent, Topology, and other
  record owners define those rules.

  Store telemetry uses `[:jido, :persistence, :store, :start | :stop]`. It
  reports the operation, adapter module, and result status. It does not report
  keys, values, tokens, or adapter options.
  """

  alias Jido.Persistence.AdapterOps
  alias Jido.Telemetry.Semantic

  @type config :: {module(), keyword()}
  @type condition :: :not_found | binary() | {:token, nonempty_binary()}

  @doc "Validates a byte adapter and returns its normalized configuration."
  @spec open(module() | config()) :: {:ok, config()} | {:error, term()}
  def open(config) do
    with {:ok, {adapter, opts} = normalized} <- normalize_result(config),
         :ok <- validate_adapter(adapter, opts) do
      {:ok, normalized}
    else
      {:ok, nil} -> {:error, :persistence_not_configured}
      {:error, _reason} = error -> error
    end
  end

  @doc "Returns bytes and the condition from one read of a validated store."
  @spec read(config(), binary()) :: {:ok, binary(), condition()} | {:error, term()}
  def read({adapter, opts}, key)
      when is_atom(adapter) and is_list(opts) and is_binary(key) do
    if Keyword.keyword?(opts) do
      observe(:load, adapter, fn ->
        AdapterOps.protect(:get, fn -> AdapterOps.get(adapter, key, opts) end)
      end)
    else
      {:error, {:invalid_persistence_config, :options}}
    end
  end

  def read(_config, _key), do: {:error, {:invalid_store_input, :read}}

  @doc "Atomically writes bytes when the supplied read condition still holds."
  @spec compare_and_swap(config(), binary(), condition(), binary()) ::
          :ok | {:error, term()}
  def compare_and_swap({adapter, opts}, key, expected, value)
      when is_atom(adapter) and is_list(opts) and is_binary(key) and is_binary(value) do
    with true <- Keyword.keyword?(opts),
         :ok <- validate_condition(expected) do
      observe(:compare_and_swap, adapter, fn ->
        AdapterOps.compare_and_swap(adapter, key, expected, value, opts)
      end)
    else
      false -> {:error, {:rejected, {:invalid_store_input, :options}}}
      {:error, _reason} = error -> error
    end
  end

  def compare_and_swap(_config, _key, _expected, _value),
    do: {:error, {:rejected, {:invalid_store_input, :compare_and_swap}}}

  @doc false
  @spec normalize_adapter(term()) :: config() | nil
  def normalize_adapter(nil), do: nil
  def normalize_adapter(false), do: nil

  def normalize_adapter({adapter, opts}) when is_atom(adapter) and is_list(opts) do
    if Keyword.keyword?(opts) do
      {adapter, opts}
    else
      raise ArgumentError, "persistence adapter options must be a keyword list"
    end
  end

  def normalize_adapter(adapter) when is_atom(adapter), do: {adapter, []}

  def normalize_adapter(config) do
    raise ArgumentError, "invalid Jido persistence adapter: #{inspect(config)}"
  end

  defp normalize_result(config) do
    {:ok, normalize_adapter(config)}
  rescue
    error -> {:error, {:invalid_persistence_config, error}}
  end

  defp validate_adapter(adapter, opts) do
    with {:module, ^adapter} <- Code.ensure_loaded(adapter),
         true <- function_exported?(adapter, :get, 2),
         true <- function_exported?(adapter, :compare_and_swap, 4),
         :ok <- validate_adapter_options(adapter, opts) do
      :ok
    else
      {:error, {:invalid_persistence_options, _, _}} = error -> error
      _other -> invalid_adapter(adapter)
    end
  end

  defp validate_adapter_options(adapter, opts) do
    if function_exported?(adapter, :validate_options, 1) do
      case adapter.validate_options(opts) do
        :ok -> :ok
        {:error, reason} -> {:error, {:invalid_persistence_options, adapter, reason}}
        result -> {:error, {:invalid_persistence_options, adapter, {:invalid_result, result}}}
      end
    else
      :ok
    end
  rescue
    error -> {:error, {:invalid_persistence_options, adapter, {:error, error}}}
  catch
    kind, reason -> {:error, {:invalid_persistence_options, adapter, {kind, reason}}}
  end

  defp invalid_adapter(adapter), do: {:error, {:invalid_persistence_adapter, adapter}}

  defp validate_condition(:not_found), do: :ok
  defp validate_condition(value) when is_binary(value), do: :ok

  defp validate_condition({:token, token}) when is_binary(token) and byte_size(token) > 0,
    do: :ok

  defp validate_condition(_value),
    do: {:error, {:rejected, {:invalid_store_input, :condition}}}

  defp observe(operation, adapter, fun) do
    Semantic.with_span(
      [:jido, :persistence, :store],
      %{operation: operation, adapter_module: adapter},
      %{},
      fun
    )
  end
end
