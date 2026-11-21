defmodule Jido.Test.AI.LiveTrace do
  @moduledoc false

  @measurement_keys [
    :duration,
    :model_calls,
    :tool_calls,
    :retries,
    :reasoning_steps,
    :input_tokens,
    :output_tokens,
    :cache_read_tokens,
    :cache_write_tokens,
    :reasoning_tokens,
    :total_cost
  ]

  @metadata_keys [
    :agent_id,
    :agent_name,
    :conversation_id,
    :finish_reason,
    :http_status,
    :mode,
    :model,
    :operation,
    :provider,
    :reasoning_method,
    :reasoning_name,
    :request_id,
    :run_id,
    :session_id,
    :status,
    :thread_id,
    :transport,
    :turn_id
  ]

  @usage_keys [
    :input_tokens,
    :output_tokens,
    :total_tokens,
    :cache_read_tokens,
    :cache_write_tokens,
    :reasoning_tokens,
    :total_cost
  ]

  def write!(path, events, result) do
    path = Path.expand(path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, events |> document(result) |> JSON.encode!())
    path
  end

  def document(events, result) do
    %{
      schema_version: 1,
      result: safe_result(result),
      events: Enum.map(events, &sanitize_event/1)
    }
  end

  defp sanitize_event({event, measurements, metadata}) do
    %{
      event: Enum.join(event, "."),
      measurements: safe_measurements(measurements),
      metadata: safe_metadata(metadata)
    }
  end

  defp safe_result(result) do
    result
    |> Map.take([:status, :model_calls, :reasoning_steps, :retries])
    |> Map.new(fn {key, value} -> {key, portable(value)} end)
    |> Map.put(:usage, numeric_fields(Map.get(result, :usage, %{}), @usage_keys))
  end

  defp safe_measurements(measurements) do
    measurements
    |> numeric_fields(@measurement_keys)
    |> rename_duration()
  end

  defp safe_metadata(metadata) do
    metadata
    |> Map.put_new(:conversation_id, conversation_id(metadata))
    |> Map.take(@metadata_keys)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new(fn {key, value} -> {key, portable(value)} end)
  end

  defp numeric_fields(value, keys) when is_map(value) do
    value
    |> Map.take(keys)
    |> Enum.filter(fn {_key, field} -> is_number(field) end)
    |> Map.new()
  end

  defp numeric_fields(_value, _keys), do: %{}

  defp rename_duration(%{duration: duration} = measurements) when is_integer(duration) do
    measurements
    |> Map.delete(:duration)
    |> Map.put(:duration_us, System.convert_time_unit(duration, :native, :microsecond))
  end

  defp rename_duration(measurements), do: measurements

  defp conversation_id(metadata) do
    metadata[:conversation_id] || get_in(metadata, [:request_options, :conversation_id])
  end

  defp portable(%LLMDB.Model{id: id}) when is_binary(id), do: id
  defp portable(value) when is_atom(value), do: Atom.to_string(value)
  defp portable(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp portable(_value), do: "[redacted]"
end
