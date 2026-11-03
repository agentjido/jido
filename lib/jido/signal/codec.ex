defmodule Jido.Signal.Codec do
  import Bitwise, only: [band: 2]

  @moduledoc """
  Encodes and decodes Signals through the canonical CloudEvents map.

  JSON is the default format. Use `format: :erlang_term` for trusted
  Erlang/Elixir systems.

  The maximum encoded or decoded payload size is 10 MB. Set
  `:max_payload_bytes` for one call, or configure `:max_payload_bytes` for the
  `:jido` application.
  """

  alias Jido.Signal.Boundary
  alias Jido.Joi
  alias Jido.Signal

  @default_max_payload_bytes 10_000_000
  @core_names ~w[
    specversion id source type subject time
    datacontenttype dataschema data data_base64
  ]
  @legacy_wire_version_key "jido_schema_version"
  @legacy_wire_versions [1, 2]

  @type format :: :json | :erlang_term

  @doc false
  @spec valid_utf8?(binary()) :: boolean()
  def valid_utf8?(<<chunk::56, rest::binary>>) when band(chunk, 0x80808080808080) == 0,
    do: valid_utf8?(rest)

  def valid_utf8?(rest), do: String.valid?(rest)

  @doc false
  @spec boundary_value(term()) :: term()
  def boundary_value(value), do: Boundary.sanitize(value, :transport)

  @doc false
  @spec boundary_preview(term(), keyword()) :: String.t()
  def boundary_preview(value, opts \\ []), do: Boundary.preview(value, :transport, opts)

  @doc "Parses a complete CloudEvents structured-mode map."
  @spec from_map(map()) :: {:ok, Signal.t()} | {:error, String.t()}
  def from_map(map) when is_map(map) do
    with {:ok, attrs} <- normalize_attribute_keys(map),
         :ok <- validate_specversion(attrs),
         :ok <- validate_legacy_wire_version(attrs),
         {:ok, data, data_present?, data_base64?} <- extract_data(attrs),
         {:ok, extensions} <- extract_extensions(attrs) do
      parse_signal(attrs, data, data_present?, data_base64?, extensions)
    end
  end

  def from_map(_map), do: {:error, "parse error: expected a map"}

  @doc "Returns the canonical CloudEvents structured-mode map."
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

  defp normalize_attribute_keys(map) do
    Enum.reduce_while(Map.to_list(map), {:ok, %{}}, fn {key, value}, {:ok, normalized} ->
      with {:ok, key} <- normalize_attribute_key(key),
           false <- Map.has_key?(normalized, key) do
        {:cont, {:ok, Map.put(normalized, key, value)}}
      else
        true -> {:halt, {:error, "parse error: duplicate attribute #{inspect(key)}"}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_attribute_key(key) when is_atom(key), do: {:ok, Atom.to_string(key)}

  defp normalize_attribute_key(key) when is_binary(key) do
    if String.valid?(key),
      do: {:ok, key},
      else: {:error, "parse error: attribute names must be valid UTF-8 strings"}
  end

  defp normalize_attribute_key(key),
    do: {:error, "parse error: attribute keys must be atoms or strings, got: #{inspect(key)}"}

  defp extract_data(attrs) do
    case {Map.fetch(attrs, "data"), Map.fetch(attrs, "data_base64")} do
      {{:ok, _data}, {:ok, _encoded}} ->
        {:error, "parse error: data and data_base64 are mutually exclusive"}

      {{:ok, data}, :error} ->
        {:ok, data, true, is_binary(data) and not String.valid?(data)}

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

  defp extract_extensions(attrs) do
    attrs
    |> Map.drop(@core_names ++ [@legacy_wire_version_key])
    |> Map.reject(fn {_name, value} -> is_nil(value) end)
    |> Signal.normalize_extensions()
    |> case do
      {:ok, extensions} -> {:ok, extensions}
      {:error, reason} -> {:error, "parse error: #{reason}"}
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

    case Joi.parse(Signal.schema(), signal) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, "parse error: #{Joi.prettify_errors(errors)}"}
    end
  end

  defp normalize_specversion("1.0.2"), do: "1.0"
  defp normalize_specversion(value), do: value

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

  @doc "Encodes one Signal or a list of Signals."
  @spec serialize(Signal.t() | [Signal.t()], keyword()) ::
          {:ok, binary()} | {:error, term()}
  def serialize(signal_or_signals, opts \\ [])

  def serialize(signal_or_signals, opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      do_serialize(signal_or_signals, opts)
    else
      {:error, {:invalid_options, "expected a keyword list"}}
    end
  end

  def serialize(_signal_or_signals, _opts),
    do: {:error, {:invalid_options, "expected a keyword list"}}

  @doc "Encodes one Signal or a list of Signals, or raises."
  @spec serialize!(Signal.t() | [Signal.t()], keyword()) :: binary() | no_return()
  def serialize!(signal_or_signals, opts \\ []) do
    case serialize(signal_or_signals, opts) do
      {:ok, binary} -> binary
      {:error, reason} -> raise RuntimeError, "serialization failed: #{inspect(reason)}"
    end
  end

  defp do_serialize(signal_or_signals, opts) do
    with {:ok, format} <- format(opts),
         {:ok, wire_data} <- to_wire_data(signal_or_signals),
         {:ok, binary} <- encode(wire_data, format),
         :ok <- check_payload_size(binary, opts) do
      {:ok, binary}
    end
  rescue
    exception -> {:error, {:serialization_failed, Exception.message(exception)}}
  end

  @doc "Decodes one Signal or a list of Signals."
  @spec deserialize(binary(), keyword()) ::
          {:ok, Signal.t() | [Signal.t()]} | {:error, term()}
  def deserialize(binary, opts \\ [])

  def deserialize(binary, opts) when is_binary(binary) and is_list(opts) do
    if Keyword.keyword?(opts) do
      with {:ok, format} <- format(opts),
           :ok <- check_payload_size(binary, opts),
           {:ok, wire_data} <- decode(binary, format),
           :ok <- check_decoded_size(wire_data, format, opts) do
        from_wire_data(wire_data)
      end
    else
      {:error, {:invalid_options, "expected a keyword list"}}
    end
  rescue
    exception -> {:error, {:deserialization_failed, Exception.message(exception)}}
  end

  def deserialize(binary, _opts) when not is_binary(binary),
    do: {:error, {:invalid_payload, "expected a binary"}}

  def deserialize(_binary, _opts), do: {:error, {:invalid_options, "expected a keyword list"}}

  defp to_wire_data(%Signal{} = signal), do: {:ok, to_map(signal)}

  defp to_wire_data(signals) when is_list(signals) do
    signals
    |> Enum.reduce_while({:ok, []}, fn
      %Signal{} = signal, {:ok, acc} ->
        {:cont, {:ok, [to_map(signal) | acc]}}

      value, _acc ->
        {:halt, {:error, {:invalid_signal, "expected a Signal, got: #{inspect(value)}"}}}
    end)
    |> case do
      {:ok, wire_data} -> {:ok, Enum.reverse(wire_data)}
      error -> error
    end
  end

  defp to_wire_data(value),
    do: {:error, {:invalid_signal, "expected a Signal or list of Signals, got: #{inspect(value)}"}}

  defp from_wire_data(data) when is_list(data) do
    data
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case from_wire_item(item) do
        {:ok, signal} -> {:cont, {:ok, [signal | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, signals} -> {:ok, Enum.reverse(signals)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp from_wire_data(data), do: from_wire_item(data)

  defp from_wire_item(data) when is_map(data), do: from_map(data)

  defp from_wire_item(data),
    do: {:error, {:invalid_wire_data, "expected a map, got: #{inspect(data)}"}}

  defp format(opts) do
    case Keyword.get(opts, :format, :json) do
      format when format in [:json, :erlang_term] -> {:ok, format}
      format -> {:error, {:unsupported_format, format}}
    end
  end

  defp encode(data, :json) do
    if json_value?(data) do
      {:ok, JSON.encode!(data)}
    else
      {:error, {:json_encode_failed, "Signal data must contain JSON values or binary data"}}
    end
  rescue
    error -> {:error, {:json_encode_failed, Exception.message(error)}}
  end

  defp encode(data, :erlang_term), do: {:ok, :erlang.term_to_binary(data)}

  defp decode(binary, :json) do
    case JSON.decode(binary) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, {:json_decode_failed, inspect(reason)}}
    end
  end

  defp decode(binary, :erlang_term) do
    case binary do
      <<131, 80, _rest::binary>> ->
        {:error, {:erlang_term_decode_failed, "compressed Erlang terms are not accepted"}}

      _uncompressed ->
        binary
        |> :erlang.binary_to_term([:safe])
        |> validate_wire_shape()
    end
  rescue
    error in ArgumentError -> {:error, {:erlang_term_decode_failed, Exception.message(error)}}
  end

  defp validate_wire_shape(data) when is_map(data), do: {:ok, data}

  defp validate_wire_shape(data) when is_list(data) do
    case Enum.reduce_while(data, :ok, fn
           item, :ok when is_map(item) -> {:cont, :ok}
           item, :ok -> {:halt, {:error, item}}
         end) do
      :ok -> {:ok, data}
      {:error, item} -> invalid_wire_shape(item)
    end
  end

  defp validate_wire_shape(data), do: invalid_wire_shape(data)

  defp invalid_wire_shape(data),
    do: {:error, {:invalid_wire_data, "expected a map, got: #{inspect(data)}"}}

  defp check_payload_size(binary, opts), do: check_size(byte_size(binary), opts)

  defp check_size(size, opts), do: check_limit(size, payload_limit(opts))

  defp payload_limit(opts) do
    Keyword.get_lazy(opts, :max_payload_bytes, fn ->
      Application.get_env(:jido, :max_payload_bytes, @default_max_payload_bytes)
    end)
  end

  defp check_limit(size, max) do
    if is_integer(max) and max >= 0 do
      if size <= max do
        :ok
      else
        {:error, {:payload_too_large, size, max}}
      end
    else
      {:error, {:invalid_max_payload_bytes, max}}
    end
  end

  defp check_decoded_size(_wire_data, :json, _opts), do: :ok

  defp check_decoded_size(wire_data, :erlang_term, opts) do
    max = payload_limit(opts)

    # external_size is an upper bound. It can prove acceptance, but only the
    # canonical encoded size can determine the error and its exact byte count.
    if is_integer(max) and max >= 0 and :erlang.external_size(wire_data) <= max do
      :ok
    else
      wire_data
      |> :erlang.term_to_iovec()
      |> :erlang.iolist_size()
      |> check_limit(max)
    end
  end

  defp json_value?(nil), do: true
  defp json_value?(value) when is_boolean(value) or is_number(value), do: true
  defp json_value?(value) when is_binary(value), do: valid_utf8?(value)
  defp json_value?([]), do: true
  defp json_value?([head | tail]) when is_list(tail), do: json_value?(head) and json_value?(tail)

  defp json_value?(value) when is_map(value) and not is_struct(value) do
    Enum.all?(value, fn {key, item} ->
      is_binary(key) and String.valid?(key) and json_value?(item)
    end)
  end

  defp json_value?(_value), do: false
end
