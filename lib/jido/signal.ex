defmodule Jido.Signal do
  @moduledoc """
  Defines the structure and behavior of a Signal in the Jido system.
  This is a local implementation of the CloudEvents specification v1.0.
  """

  use TypedStruct

  typedstruct do
    field(:specversion, String.t(), default: "1.0")
    field(:id, String.t(), enforce: true)
    field(:source, String.t(), enforce: true)
    field(:type, String.t(), enforce: true)
    field(:subject, String.t())
    field(:time, String.t())
    field(:datacontenttype, String.t())
    field(:dataschema, String.t())
    field(:data, term())
    field(:extensions, %{optional(String.t()) => term()}, default: %{})
  end

  @doc """
  Creates a new Signal struct.

  ## Parameters

  - `attrs`: A map containing the Signal attributes.

  ## Returns

  `{:ok, Signal.t()}` if the attributes are valid, `{:error, String.t()}` otherwise.

  ## Examples

      iex> Jido.Signal.new(%{type: "example.event", source: "/example", id: "123"})
      {:ok, %Jido.Signal{type: "example.event", source: "/example", id: "123", ...}}

  """
  @spec new(map()) :: {:ok, t()} | {:error, String.t()}
  def new(attrs) when is_map(attrs) do
    defaults = %{
      "specversion" => "1.0",
      "id" => Jido.Util.generate_id(),
      "time" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    attrs
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.merge(defaults, fn _k, user_val, _default_val -> user_val end)
    |> from_map()
  end

  @doc """
  Creates a new Signal struct from a map.

  ## Parameters

  - `map`: A map containing the Signal attributes.

  ## Returns

  `{:ok, Signal.t()}` if the map is valid, `{:error, String.t()}` otherwise.

  ## Examples

      iex> Jido.Signal.from_map(%{"type" => "example.event", "source" => "/example", "id" => "123"})
      {:ok, %Jido.Signal{type: "example.event", source: "/example", id: "123", ...}}

  """
  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(map) when is_map(map) do
    {event_data, ctx_attrs} = Map.pop(map, "data")

    {_, extension_attrs} =
      Map.split(ctx_attrs, [
        "specversion",
        "type",
        "source",
        "id",
        "subject",
        "time",
        "datacontenttype",
        "dataschema",
        "data"
      ])

    with :ok <- parse_specversion(ctx_attrs),
         {:ok, type} <- parse_type(ctx_attrs),
         {:ok, source} <- parse_source(ctx_attrs),
         {:ok, id} <- parse_id(ctx_attrs),
         {:ok, subject} <- parse_subject(ctx_attrs),
         {:ok, time} <- parse_time(ctx_attrs),
         {:ok, datacontenttype} <- parse_datacontenttype(ctx_attrs),
         {:ok, dataschema} <- parse_dataschema(ctx_attrs),
         {:ok, data} <- parse_data(event_data),
         {:ok, extensions} <- validated_extensions_attributes(extension_attrs) do
      datacontenttype =
        if is_nil(datacontenttype) and not is_nil(data),
          do: "application/json",
          else: datacontenttype

      event = %__MODULE__{
        type: type,
        source: source,
        id: id,
        subject: subject,
        time: time,
        datacontenttype: datacontenttype,
        dataschema: dataschema,
        data: data,
        extensions: extensions
      }

      {:ok, event}
    else
      {:error, parse_error} ->
        {:error, "parse error: #{parse_error}"}
    end
  end

  defp parse_specversion(%{"specversion" => "1.0"}), do: :ok
  defp parse_specversion(%{"specversion" => x}), do: {:error, "unexpected specversion #{x}"}
  defp parse_specversion(_), do: {:error, "missing specversion"}

  defp parse_type(%{"type" => type}) when byte_size(type) > 0, do: {:ok, type}
  defp parse_type(_), do: {:error, "missing type"}

  defp parse_source(%{"source" => source}) when byte_size(source) > 0, do: {:ok, source}
  defp parse_source(_), do: {:error, "missing source"}

  defp parse_id(%{"id" => id}) when byte_size(id) > 0, do: {:ok, id}
  defp parse_id(_), do: {:error, "missing id"}

  defp parse_subject(%{"subject" => sub}) when byte_size(sub) > 0, do: {:ok, sub}
  defp parse_subject(%{"subject" => ""}), do: {:error, "subject given but empty"}
  defp parse_subject(_), do: {:ok, nil}

  defp parse_time(%{"time" => time}) when byte_size(time) > 0, do: {:ok, time}
  defp parse_time(%{"time" => ""}), do: {:error, "time given but empty"}
  defp parse_time(_), do: {:ok, nil}

  defp parse_datacontenttype(%{"datacontenttype" => ct}) when byte_size(ct) > 0, do: {:ok, ct}

  defp parse_datacontenttype(%{"datacontenttype" => ""}),
    do: {:error, "datacontenttype given but empty"}

  defp parse_datacontenttype(_), do: {:ok, nil}

  defp parse_dataschema(%{"dataschema" => schema}) when byte_size(schema) > 0, do: {:ok, schema}
  defp parse_dataschema(%{"dataschema" => ""}), do: {:error, "dataschema given but empty"}
  defp parse_dataschema(_), do: {:ok, nil}

  defp parse_data(""), do: {:error, "data field given but empty"}
  defp parse_data(data), do: {:ok, data}

  defp try_decode(key, val) when is_binary(val) do
    case Jason.decode(val) do
      {:ok, val_map} -> {key, val_map}
      _ -> {key, val}
    end
  end

  defp try_decode(key, val), do: {key, val}

  defp validated_extensions_attributes(extension_attrs) do
    invalid =
      extension_attrs
      |> Map.keys()
      |> Enum.map(fn key -> {key, valid_extension_attribute_name(key)} end)
      |> Enum.filter(fn {_, valid?} -> not valid? end)

    case invalid do
      [] ->
        extensions = Map.new(extension_attrs, fn {key, val} -> try_decode(key, val) end)
        {:ok, extensions}

      _ ->
        {:error,
         "invalid extension attributes: #{Enum.map(invalid, fn {key, _} -> inspect(key) end)}"}
    end
  end

  defp valid_extension_attribute_name(name) do
    name =~ ~r/^[a-z0-9]+$/
  end
end
