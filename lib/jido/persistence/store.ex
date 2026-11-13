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

  alias Jido.Error
  alias Jido.Telemetry.Semantic

  @type key :: binary()
  @type value :: binary()
  @type token :: nonempty_binary()
  @type options :: keyword()
  @type condition :: :not_found | value() | {:token, token()}
  @type config :: {module(), keyword()}
  @type declaration :: module() | config() | nil | false
  @type cursor :: binary() | nil

  @doc "Validates Store options before an operation starts."
  @callback validate_options(options()) :: :ok | {:error, term()}

  @doc "Gets one binary value and an optional opaque read token."
  @callback get(key(), options()) ::
              {:ok, value()} | {:ok, value(), token()} | {:error, term()}

  @doc "Stores one value for explicit maintenance and replaces any prior value."
  @callback put(key(), value(), options()) :: :ok | {:error, term()}

  @doc "Atomically writes one value when the supplied read condition still holds."
  @callback compare_and_swap(key(), condition(), value(), options()) ::
              :ok | {:error, term()}

  @doc "Physically deletes one value for explicit maintenance."
  @callback delete(key(), options()) :: :ok | {:error, term()}

  @doc "Lists one page of key/value pairs for inspection and export."
  @callback scan(binary(), cursor(), pos_integer(), options()) ::
              {:ok, [{key(), value()}], cursor()} | {:error, term()}

  @optional_callbacks put: 3, scan: 4

  @doc "Validates a byte adapter and returns its normalized configuration."
  @spec open(declaration()) :: {:ok, config()} | {:error, term()}
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
        protect(:get, fn -> get(adapter, key, opts) end)
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
        safe_compare_and_swap(adapter, key, expected, value, opts)
      end)
    else
      false -> {:error, {:rejected, {:invalid_store_input, :options}}}
      {:error, _reason} = error -> error
    end
  end

  def compare_and_swap(_config, _key, _expected, _value),
    do: {:error, {:rejected, {:invalid_store_input, :compare_and_swap}}}

  @doc "Physically deletes one key from a validated Store."
  @spec delete(config(), binary()) :: :ok | {:error, term()}
  def delete({adapter, opts}, key)
      when is_atom(adapter) and is_list(opts) and is_binary(key) do
    cond do
      not Keyword.keyword?(opts) ->
        {:error, {:invalid_persistence_config, :options}}

      true ->
        observe(:delete, adapter, fn -> safe_delete(adapter, key, opts) end)
    end
  end

  def delete(_config, _key), do: {:error, {:invalid_store_input, :delete}}

  @doc "Returns one optional scan page for inspection tools."
  @spec scan(config(), binary(), keyword()) ::
          {:ok, [{binary(), binary()}], cursor()} | {:error, term()}
  def scan(config, prefix, opts \\ [])

  def scan({adapter, adapter_opts}, prefix, opts)
      when is_atom(adapter) and is_list(adapter_opts) and is_binary(prefix) and is_list(opts) do
    with true <- Keyword.keyword?(adapter_opts) and Keyword.keyword?(opts),
         :ok <- validate_scan_options(opts) do
      if function_exported?(adapter, :scan, 4) do
        cursor = Keyword.get(opts, :cursor)
        limit = Keyword.get(opts, :limit, 100)

        observe(:scan, adapter, fn ->
          protect(:scan, fn -> adapter.scan(prefix, cursor, limit, adapter_opts) end)
        end)
      else
        {:error, :scan_not_supported}
      end
    else
      false -> {:error, {:invalid_store_input, :scan}}
      {:error, _reason} = error -> error
    end
  end

  def scan(_config, _prefix, _opts), do: {:error, {:invalid_store_input, :scan}}

  @doc false
  def protect(operation, fun) do
    fun.()
  rescue
    error -> persistence_failure(operation, :error, error)
  catch
    kind, reason -> persistence_failure(operation, kind, reason)
  end

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
         true <- function_exported?(adapter, :validate_options, 1),
         true <- function_exported?(adapter, :get, 2),
         true <- function_exported?(adapter, :compare_and_swap, 4),
         true <- function_exported?(adapter, :delete, 2),
         :ok <- validate_adapter_options(adapter, opts) do
      :ok
    else
      {:error, {:invalid_persistence_options, _, _}} = error -> error
      _other -> invalid_adapter(adapter)
    end
  end

  defp validate_adapter_options(adapter, opts) do
    case adapter.validate_options(opts) do
      :ok -> :ok
      {:error, reason} -> {:error, {:invalid_persistence_options, adapter, reason}}
      result -> {:error, {:invalid_persistence_options, adapter, {:invalid_result, result}}}
    end
  rescue
    error -> {:error, {:invalid_persistence_options, adapter, {:error, error}}}
  catch
    kind, reason -> {:error, {:invalid_persistence_options, adapter, {kind, reason}}}
  end

  defp invalid_adapter(adapter), do: {:error, {:invalid_persistence_adapter, adapter}}

  defp get(adapter, key, opts) do
    case adapter.get(key, opts) do
      {:ok, value} when is_binary(value) ->
        {:ok, value, value}

      {:ok, value, token} when is_binary(value) and is_binary(token) and byte_size(token) > 0 ->
        {:ok, value, {:token, token}}

      result when is_tuple(result) and tuple_size(result) > 2 and elem(result, 0) == :ok ->
        invalid_adapter_result(:get, :invalid_token_read)

      {:error, _reason} = error ->
        error

      result ->
        invalid_adapter_result(:get, result)
    end
  end

  defp safe_compare_and_swap(adapter, key, expected, value, opts) do
    result =
      try do
        adapter.compare_and_swap(key, expected, value, opts)
      rescue
        error -> {:callback_fault, :error, error}
      catch
        kind, reason -> {:callback_fault, kind, reason}
      end

    case result do
      :ok ->
        :ok

      {:error, :conflict} = error ->
        error

      {:error, {:rejected, _reason}} = error ->
        error

      {:error, :indeterminate} = error ->
        error

      {:error, {:indeterminate, _reason}} = error ->
        error

      {:error, reason} ->
        {:error, {:indeterminate, reason}}

      {:callback_fault, kind, reason} ->
        {:error, {:indeterminate, persistence_failure_value(:compare_and_swap, kind, reason)}}

      invalid ->
        {:error, {:indeterminate, invalid_adapter_result_value(:compare_and_swap, invalid)}}
    end
  end

  defp safe_delete(adapter, key, opts) do
    result =
      try do
        adapter.delete(key, opts)
      rescue
        error -> {:callback_fault, :error, error}
      catch
        kind, reason -> {:callback_fault, kind, reason}
      end

    case result do
      :ok ->
        :ok

      {:error, :conflict} = error ->
        error

      {:error, {:rejected, _reason}} = error ->
        error

      {:error, :indeterminate} = error ->
        error

      {:error, {:indeterminate, _reason}} = error ->
        error

      {:error, reason} ->
        {:error, {:indeterminate, reason}}

      {:callback_fault, kind, reason} ->
        {:error, {:indeterminate, persistence_failure_value(:delete, kind, reason)}}

      invalid ->
        {:error, {:indeterminate, invalid_adapter_result_value(:delete, invalid)}}
    end
  end

  defp invalid_adapter_result(operation, result),
    do: {:error, invalid_adapter_result_value(operation, result)}

  defp persistence_failure(operation, kind, reason),
    do: {:error, persistence_failure_value(operation, kind, reason)}

  defp invalid_adapter_result_value(operation, result) do
    Error.execution_error("Persistence adapter returned an invalid result",
      details: %{
        code: :persistence_invalid_callback_result,
        operation: operation,
        result: result
      }
    )
  end

  defp persistence_failure_value(operation, kind, reason) do
    Error.execution_error("Persistence adapter operation failed",
      details: %{
        code: :persistence_callback_failed,
        operation: operation,
        kind: kind,
        reason: reason
      }
    )
  end

  defp validate_condition(:not_found), do: :ok
  defp validate_condition(value) when is_binary(value), do: :ok

  defp validate_condition({:token, token}) when is_binary(token) and byte_size(token) > 0,
    do: :ok

  defp validate_condition(_value),
    do: {:error, {:rejected, {:invalid_store_input, :condition}}}

  defp validate_scan_options(opts) do
    keys = Keyword.keys(opts)

    cond do
      keys -- [:cursor, :limit] != [] ->
        {:error, {:invalid_store_input, :scan_options}}

      keys -- Enum.uniq(keys) != [] ->
        {:error, {:invalid_store_input, :scan_options}}

      not (is_nil(Keyword.get(opts, :cursor)) or is_binary(Keyword.get(opts, :cursor))) ->
        {:error, {:invalid_store_input, :scan_cursor}}

      not (is_integer(Keyword.get(opts, :limit, 100)) and Keyword.get(opts, :limit, 100) > 0) ->
        {:error, {:invalid_store_input, :scan_limit}}

      true ->
        :ok
    end
  end

  defp observe(operation, adapter, fun) do
    Semantic.with_span(
      [:jido, :persistence, :store],
      %{operation: operation, adapter_module: adapter},
      %{},
      fun
    )
  end
end
