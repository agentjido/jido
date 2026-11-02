defmodule Jido.Signal.Codec do
  @moduledoc false

  alias Jido.Signal
  alias Jido.Signal.Context
  alias Jido.Signal.ID

  @core_names ~w[
    specversion id source type subject time
    datacontenttype dataschema data data_base64
  ]
  @constructor_names ["extensions" | @core_names]
  @legacy_wire_version_key "jido_schema_version"
  @legacy_wire_versions [1, 2]

  @doc false
  @spec new(map()) :: {:ok, Signal.t()} | {:error, String.t()}
  def new(map) when is_map(map) do
    with {:ok, attrs} <- normalize_keys(map) do
      attrs
      |> Map.put_new_lazy("id", &ID.generate!/0)
      |> Map.put_new("specversion", "1.0")
      |> from_normalized_map(:constructor)
    end
  end

  @doc false
  @spec from_map(map()) :: {:ok, Signal.t()} | {:error, String.t()}
  def from_map(map) when is_map(map) do
    with {:ok, attrs} <- normalize_keys(map), do: from_normalized_map(attrs, :wire)
  end

  def from_map(_map), do: {:error, "parse error: expected a map"}

  @doc false
  @spec to_map(Signal.t()) :: map()
  def to_map(%Signal{} = signal) do
    extensions =
      case Context.normalize(signal.extensions) do
        {:ok, extensions} -> extensions
        {:error, reason} -> raise ArgumentError, "invalid Signal extensions: #{reason}"
      end

    signal
    |> core_map()
    |> Map.merge(extensions)
  end

  @doc false
  @spec normalize_keys(map()) :: {:ok, map()} | {:error, String.t()}
  def normalize_keys(map) when is_map(map) do
    Enum.reduce_while(Map.to_list(map), {:ok, %{}}, fn {key, value}, {:ok, normalized} ->
      with {:ok, key} <- normalize_key(key),
           false <- Map.has_key?(normalized, key) do
        {:cont, {:ok, Map.put(normalized, key, value)}}
      else
        true -> {:halt, {:error, "parse error: duplicate attribute #{inspect(key)}"}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp from_normalized_map(attrs, boundary) do
    with :ok <- validate_specversion(attrs),
         :ok <- validate_legacy_wire_version(attrs),
         {:ok, data, data_present?, data_base64?} <- extract_data(attrs),
         {:ok, extensions} <- extract_extensions(attrs, boundary) do
      parse_signal(attrs, data, data_present?, data_base64?, extensions)
    end
  end

  defp extract_extensions(attrs, :constructor) do
    explicit = Map.get(attrs, "extensions", %{})
    unknown = Map.drop(attrs, @constructor_names ++ [@legacy_wire_version_key])

    with {:ok, explicit} <- Context.normalize(explicit),
         {:ok, unknown} <- Context.normalize(unknown),
         :ok <- reject_duplicate_extensions(explicit, unknown) do
      {:ok, Map.merge(unknown, explicit)}
    else
      {:error, reason} -> {:error, "parse error: #{reason}"}
    end
  end

  defp extract_extensions(attrs, :wire) do
    attrs
    |> Map.drop(@core_names ++ [@legacy_wire_version_key])
    |> Map.reject(fn {_name, value} -> is_nil(value) end)
    |> Context.normalize()
    |> case do
      {:ok, extensions} -> {:ok, extensions}
      {:error, reason} -> {:error, "parse error: #{reason}"}
    end
  end

  defp reject_duplicate_extensions(explicit, unknown) do
    case Enum.find(Map.keys(explicit), &Map.has_key?(unknown, &1)) do
      nil -> :ok
      name -> {:error, "duplicate extension attribute #{inspect(name)}"}
    end
  end

  defp parse_signal(attrs, data, data_present?, data_base64?, extensions) do
    signal =
      struct(Signal,
        data: data,
        data_present?: data_present?,
        data_base64?: data_base64?,
        datacontenttype: Map.get(attrs, "datacontenttype"),
        dataschema: Map.get(attrs, "dataschema"),
        extensions: extensions,
        id: Map.get(attrs, "id"),
        source: Map.get(attrs, "source"),
        specversion: normalize_specversion(Map.get(attrs, "specversion")),
        subject: Map.get(attrs, "subject"),
        time: normalize_time(Map.get(attrs, "time")),
        type: Map.get(attrs, "type")
      )

    case Zoi.parse(Signal.schema(), signal) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, "parse error: #{Zoi.prettify_errors(errors)}"}
    end
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
    if base64? or not Jido.Signal.UTF8.valid?(data),
      do: %{"data_base64" => Base.encode64(data)},
      else: %{"data" => data}
  end

  defp encode_data(data, _present?, _base64?), do: %{"data" => data}

  defp extract_data(attrs) do
    case {Map.fetch(attrs, "data"), Map.fetch(attrs, "data_base64")} do
      {{:ok, _data}, {:ok, _encoded}} ->
        {:error, "parse error: data and data_base64 are mutually exclusive"}

      {{:ok, data}, :error} ->
        {:ok, data, true, is_binary(data) and not Jido.Signal.UTF8.valid?(data)}

      {:error, {:ok, encoded}} ->
        decode_data_base64(encoded)

      {:error, :error} ->
        {:ok, nil, false, false}
    end
  end

  defp decode_data_base64(encoded) when is_binary(encoded) do
    case Base.decode64(encoded) do
      {:ok, binary} -> {:ok, binary, true, true}
      :error -> {:error, "parse error: data_base64 must be valid Base64"}
    end
  end

  defp decode_data_base64(_encoded),
    do: {:error, "parse error: data_base64 must be a Base64 string"}

  defp normalize_specversion("1.0.2"), do: "1.0"
  defp normalize_specversion(value), do: value

  defp normalize_time(%DateTime{} = time), do: DateTime.to_iso8601(time)
  defp normalize_time(time), do: time

  defp validate_specversion(%{"specversion" => value}) when not is_nil(value), do: :ok
  defp validate_specversion(_attrs), do: {:error, "parse error: specversion is required"}

  defp validate_legacy_wire_version(%{@legacy_wire_version_key => version})
       when version in @legacy_wire_versions,
       do: :ok

  defp validate_legacy_wire_version(%{@legacy_wire_version_key => nil}), do: :ok

  defp validate_legacy_wire_version(map)
       when not is_map_key(map, @legacy_wire_version_key),
       do: :ok

  defp validate_legacy_wire_version(%{@legacy_wire_version_key => version}) do
    {:error, "parse error: unsupported jido_schema_version #{inspect(version)}"}
  end

  defp normalize_key(key) when is_atom(key), do: {:ok, Atom.to_string(key)}

  defp normalize_key(key) when is_binary(key) do
    if String.valid?(key),
      do: {:ok, key},
      else: {:error, "parse error: attribute names must be valid UTF-8 strings"}
  end

  defp normalize_key(key),
    do: {:error, "parse error: attribute keys must be atoms or strings, got: #{inspect(key)}"}
end
