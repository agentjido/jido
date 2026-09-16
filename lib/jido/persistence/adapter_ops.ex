defmodule Jido.Persistence.AdapterOps do
  @moduledoc false

  alias Jido.Error

  def get(adapter, key, opts) do
    case adapter.get(key, opts) do
      {:ok, value} when is_binary(value) ->
        {:ok, value, value}

      {:ok, value, token} when is_binary(value) and is_binary(token) and byte_size(token) > 0 ->
        {:ok, value, {:token, token}}

      {:ok, _value, _token} ->
        invalid_adapter_result(:get, :invalid_token_read)

      result when is_tuple(result) and tuple_size(result) > 2 and elem(result, 0) == :ok ->
        invalid_adapter_result(:get, :invalid_token_read)

      {:error, _reason} = error ->
        error

      result ->
        invalid_adapter_result(:get, result)
    end
  end

  def compare_and_swap(adapter, key, expected, value, opts) do
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

  def protect(operation, fun) do
    fun.()
  rescue
    error -> persistence_failure(operation, :error, error)
  catch
    kind, reason -> persistence_failure(operation, kind, reason)
  end

  defp invalid_adapter_result(operation, result) do
    {:error, invalid_adapter_result_value(operation, result)}
  end

  defp persistence_failure(operation, kind, reason) do
    {:error, persistence_failure_value(operation, kind, reason)}
  end

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
end
