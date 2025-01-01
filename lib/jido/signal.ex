defmodule Jido.Signal do
  @moduledoc """
  Defines the structure and behavior of a Signal in the Jido system.
  Implements CloudEvents specification v1.0.2 with Jido-specific extensions.
  """

  use TypedStruct

  @derive Jason.Encoder
  @derive Inspect
  typedstruct do
    field(:specversion, String.t(), default: "1.0.2")
    field(:id, String.t(), enforce: true)
    field(:source, String.t(), enforce: true)
    field(:type, String.t(), enforce: true)
    field(:subject, String.t())
    field(:time, String.t())
    field(:datacontenttype, String.t())
    field(:dataschema, String.t())
    field(:data, term())
    # Jido-specific fields
    field(:jidoinstructions, Jido.Runner.Instruction.instruction_list())
    field(:jidoopts, map())
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
      "specversion" => "1.0.2",
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
    with :ok <- parse_specversion(map),
         {:ok, type} <- parse_type(map),
         {:ok, source} <- parse_source(map),
         {:ok, id} <- parse_id(map),
         {:ok, subject} <- parse_subject(map),
         {:ok, time} <- parse_time(map),
         {:ok, datacontenttype} <- parse_datacontenttype(map),
         {:ok, dataschema} <- parse_dataschema(map),
         {:ok, data} <- parse_data(map["data"]),
         {:ok, jidoinstructions} <- parse_jidoinstructions(map["jidoinstructions"]),
         {:ok, jidoopts} <- parse_jidoopts(map["jidoopts"]) do
      event = %__MODULE__{
        specversion: "1.0.2",
        type: type,
        source: source,
        id: id,
        subject: subject,
        time: time,
        datacontenttype: datacontenttype || if(data, do: "application/json"),
        dataschema: dataschema,
        data: data,
        jidoinstructions: jidoinstructions,
        jidoopts: jidoopts
      }

      {:ok, event}
    else
      {:error, reason} -> {:error, "parse error: #{reason}"}
    end
  end

  # Parser functions for standard CloudEvents fields
  defp parse_specversion(%{"specversion" => "1.0.2"}), do: :ok
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

  defp parse_jidoinstructions(nil), do: {:ok, nil}

  defp parse_jidoinstructions(instructions) when is_list(instructions) do
    if Enum.all?(instructions, &valid_instruction?/1),
      do: {:ok, instructions},
      else: {:error, "invalid instruction format"}
  end

  defp parse_jidoinstructions(_), do: {:error, "jidoinstructions must be a list of instructions"}

  defp parse_jidoopts(nil), do: {:ok, %{}}
  defp parse_jidoopts(opts) when is_map(opts), do: {:ok, opts}
  defp parse_jidoopts(_), do: {:error, "jidoopts must be a map"}

  defp valid_instruction?({action, params}) when is_atom(action) and is_map(params), do: true
  defp valid_instruction?(_), do: false
end
