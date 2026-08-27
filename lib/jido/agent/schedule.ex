defmodule Jido.Agent.Schedule do
  @moduledoc "A canonical named Agent schedule declaration."

  alias Jido.Agent.Data
  alias Jido.Error

  @default_timezone "Etc/UTC"

  @type t :: %__MODULE__{
          name: String.t(),
          cron_expression: String.t(),
          signal_type: String.t(),
          timezone: String.t(),
          data: Data.object(),
          metadata: Data.object()
        }

  defstruct name: nil,
            cron_expression: nil,
            signal_type: nil,
            timezone: @default_timezone,
            data: %{},
            metadata: %{}

  @doc "Builds and validates one canonical schedule declaration."
  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = schedule), do: schedule |> Map.from_struct() |> new()

  def new(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs),
      do: attrs |> Map.new() |> new(),
      else: invalid_map()
  end

  def new(%{} = attrs) do
    with :ok <- known_keys(attrs),
         {:ok, name} <- name(Map.get(attrs, :name)),
         {:ok, cron_expression} <- text(Map.get(attrs, :cron_expression), :cron_expression),
         {:ok, signal_type} <- text(Map.get(attrs, :signal_type), :signal_type),
         {:ok, timezone} <- text(Map.get(attrs, :timezone, @default_timezone), :timezone),
         {:ok, data} <- object(Map.get(attrs, :data, %{}), :data),
         {:ok, metadata} <- object(Map.get(attrs, :metadata, %{}), :metadata) do
      {:ok,
       %__MODULE__{
         name: name,
         cron_expression: cron_expression,
         signal_type: signal_type,
         timezone: timezone,
         data: data,
         metadata: metadata
       }}
    end
  end

  def new(_attrs), do: invalid_map()

  @doc "Builds one canonical schedule declaration or raises its validation error."
  @spec new!(map() | keyword() | t()) :: t() | no_return()
  def new!(attrs) do
    case new(attrs) do
      {:ok, schedule} -> schedule
      {:error, error} -> raise error
    end
  end

  @doc false
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = schedule) do
    %{
      name: schedule.name,
      cron_expression: schedule.cron_expression,
      signal_type: schedule.signal_type,
      timezone: schedule.timezone,
      data: schedule.data,
      metadata: schedule.metadata
    }
  end

  defp known_keys(attrs) do
    allowed = [:name, :cron_expression, :signal_type, :timezone, :data, :metadata]

    case Enum.find(Map.keys(attrs), &(&1 not in allowed)) do
      nil -> :ok
      key -> {:error, error("unknown Agent schedule key: #{inspect(key)}", %{key: key})}
    end
  end

  defp name(value) do
    case Jido.Util.validate_name(value) do
      {:ok, name} -> {:ok, name}
      {:error, _validation_error} -> {:error, error("agent schedule name is invalid")}
    end
  end

  defp text(value, field) when is_binary(value) do
    if value != "" and String.valid?(value),
      do: {:ok, value},
      else: {:error, error("agent schedule #{field} must be nonempty valid UTF-8 text")}
  end

  defp text(_value, field),
    do: {:error, error("agent schedule #{field} must be nonempty valid UTF-8 text")}

  defp object(value, field) do
    case Data.validate_object(value) do
      :ok -> {:ok, value}
      {:error, validation_error} -> {:error, prefix(validation_error, [field])}
    end
  end

  defp invalid_map, do: {:error, error("agent schedule configuration must be a map")}

  defp error(message, details \\ %{}),
    do: Error.validation_error(message, details: details)

  defp prefix(%{details: details} = validation_error, path) when is_map(details),
    do: %{
      validation_error
      | details: Map.put(details, :path, path ++ Map.get(details, :path, []))
    }
end
