defmodule Jido.Codec.Signal.CloudEvents do
  @moduledoc false

  alias Jido.Signal

  @doc false
  @spec from_map(map()) :: {:ok, Signal.t()} | {:error, String.t()}
  def from_map(map), do: Signal.__from_cloud_events__(map)

  @doc false
  @spec to_map(Signal.t()) :: map()
  def to_map(%Signal{} = signal) do
    extensions =
      case Signal.normalize_extensions(signal.extensions) do
        {:ok, extensions} -> extensions
        {:error, reason} -> raise ArgumentError, "invalid Signal extensions: #{reason}"
      end

    signal
    |> core_map()
    |> Map.merge(extensions)
  end

  defp core_map(signal) do
    %{
      "specversion" => signal.specversion,
      "id" => signal.id,
      "source" => signal.source,
      "type" => signal.type,
      "subject" => signal.subject,
      "time" => normalize_time(signal.time),
      "datacontenttype" => signal.datacontenttype,
      "dataschema" => signal.dataschema
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.merge(encode_data(signal.data, signal.data_present?, signal.data_base64?))
  end

  defp encode_data(nil, false, _base64?), do: %{}
  defp encode_data(nil, true, _base64?), do: %{"data" => nil}

  defp encode_data(data, _present?, base64?) when is_binary(data) do
    if base64? or not String.valid?(data),
      do: %{"data_base64" => Base.encode64(data)},
      else: %{"data" => data}
  end

  defp encode_data(data, _present?, _base64?), do: %{"data" => data}

  defp normalize_time(%DateTime{} = time), do: DateTime.to_iso8601(time)
  defp normalize_time(time), do: time
end
