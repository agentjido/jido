defmodule Jido.Telemetry.Formatter do
  @moduledoc """
  Structured log formatting utilities for the Jido telemetry system.

  Provides functions to format durations, metadata, directives, and other
  telemetry data into human-readable, scannable log output.

  ## Examples

      iex> Jido.Telemetry.Formatter.format_duration(1_500_000)
      "1.5ms"

      iex> Jido.Telemetry.Formatter.format_metadata(%{agent_id: "abc123", trace_id: "xyz"})
      "agent_id=abc123 trace_id=xyz"
  """

  @default_max_length 100
  @default_value_max_length 50

  @doc """
  Convert native time to human-readable format.

  Returns a string like "1.2ms", "342μs", or "2.1s" depending on the magnitude.

  ## Examples

      iex> Formatter.format_duration(1_000)
      "1μs"

      iex> Formatter.format_duration(1_500_000)
      "1.5ms"

      iex> Formatter.format_duration(2_500_000_000)
      "2.5s"
  """
  @spec format_duration(integer() | nil) :: String.t()
  def format_duration(nil), do: "0μs"

  def format_duration(native_time) when is_integer(native_time) do
    microseconds = System.convert_time_unit(native_time, :native, :microsecond)

    cond do
      microseconds >= 1_000_000 ->
        seconds = microseconds / 1_000_000
        "#{Float.round(seconds, 2)}s"

      microseconds >= 1_000 ->
        ms = microseconds / 1_000
        "#{Float.round(ms, 2)}ms"

      true ->
        "#{microseconds}μs"
    end
  end

  def format_duration(_), do: "??"

  @doc """
  Convert native time to milliseconds.

  Returns an integer for times >= 1ms, otherwise a float with precision.

  ## Examples

      iex> Formatter.to_ms(1_500_000)
      1.5

      iex> Formatter.to_ms(5_000_000)
      5
  """
  @spec to_ms(integer() | nil) :: number()
  def to_ms(nil), do: 0

  def to_ms(native_time) when is_integer(native_time) do
    microseconds = System.convert_time_unit(native_time, :native, :microsecond)
    ms = microseconds / 1_000

    if ms == trunc(ms) do
      trunc(ms)
    else
      Float.round(ms, 3)
    end
  end

  def to_ms(_), do: 0

  @doc """
  Format metadata map into a scannable key=value string for logs.

  Handles nil values gracefully and truncates long values.

  ## Options

    * `:max_value_length` - Maximum length for individual values (default: 50)

  ## Examples

      iex> Formatter.format_metadata(%{agent_id: "abc123", trace_id: "xyz"})
      "agent_id=abc123 trace_id=xyz"

      iex> Formatter.format_metadata(%{key: nil, other: "value"})
      "other=value"

      iex> Formatter.format_metadata(nil)
      ""
  """
  @spec format_metadata(map() | nil, keyword()) :: String.t()
  def format_metadata(metadata, opts \\ [])
  def format_metadata(nil, _opts), do: ""

  def format_metadata(metadata, opts) when is_map(metadata) do
    max_value_length = Keyword.get(opts, :max_value_length, @default_value_max_length)

    metadata
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.sort_by(fn {k, _v} -> to_string(k) end)
    |> Enum.map_join(" ", fn {k, v} ->
      formatted_value = format_value(v, max_value_length)
      "#{k}=#{formatted_value}"
    end)
  end

  def format_metadata(_, _opts), do: ""

  defp format_value(value, max_length) when is_binary(value) do
    truncate_string(value, max_length)
  end

  defp format_value(value, _max_length) when is_atom(value) do
    to_string(value)
  end

  defp format_value(value, _max_length) when is_number(value) do
    to_string(value)
  end

  defp format_value(value, max_length) do
    value
    |> inspect(limit: 10, printable_limit: max_length)
    |> truncate_string(max_length)
  end

  defp truncate_string(str, max_length) when byte_size(str) <= max_length, do: str

  defp truncate_string(str, max_length) do
    String.slice(str, 0, max_length - 3) <> "..."
  end

  @doc """
  Returns a map of directive_type => count from a list of directives.

  ## Examples

      iex> directives = [%{type: :emit}, %{type: :emit}, %{type: :tool}]
      iex> Formatter.summarize_directives(directives)
      %{emit: 2, tool: 1}

      iex> Formatter.summarize_directives([])
      %{}
  """
  @spec summarize_directives(list()) :: map()
  def summarize_directives(nil), do: %{}

  def summarize_directives(directives) when is_list(directives) do
    directives
    |> Enum.map(&extract_directive_type/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
  end

  def summarize_directives(_), do: %{}

  defp extract_directive_type(%{type: type}), do: type
  defp extract_directive_type({type, _}) when is_atom(type), do: type
  defp extract_directive_type(type) when is_atom(type), do: type
  defp extract_directive_type(_), do: nil

  @doc """
  Format directive summary map for logging.

  ## Examples

      iex> Formatter.format_directive_types(%{emit: 2, tool: 1, await: 1})
      "Await=1 Emit=2 Tool=1"

      iex> Formatter.format_directive_types(%{})
      ""
  """
  @spec format_directive_types(map()) :: String.t()
  def format_directive_types(nil), do: ""
  def format_directive_types(summary) when map_size(summary) == 0, do: ""

  def format_directive_types(summary) when is_map(summary) do
    summary
    |> Enum.sort_by(fn {k, _v} -> to_string(k) end)
    |> Enum.map_join(" ", fn {type, count} ->
      formatted_type = type |> to_string() |> String.capitalize()
      "#{formatted_type}=#{count}"
    end)
  end

  def format_directive_types(_), do: ""

  @doc """
  Format signal type for logging.

  Handles atoms and strings, converting to a readable format.

  ## Examples

      iex> Formatter.format_signal_type(:user_request)
      "user_request"

      iex> Formatter.format_signal_type("api_call")
      "api_call"

      iex> Formatter.format_signal_type(nil)
      "unknown"
  """
  @spec format_signal_type(atom() | String.t() | nil) :: String.t()
  def format_signal_type(nil), do: "unknown"
  def format_signal_type(type) when is_atom(type), do: to_string(type)
  def format_signal_type(type) when is_binary(type), do: type
  def format_signal_type(_), do: "unknown"

  @doc """
  Summarize action for logging without exposing full data.

  Shows the action/module name and parameter keys but not values.

  ## Examples

      iex> Formatter.format_action({:analyze, %{query: "secret", context: %{}}})
      "{:analyze, keys: [:context, :query]}"

      iex> Formatter.format_action(MyApp.Actions.ProcessData)
      "MyApp.Actions.ProcessData"

      iex> Formatter.format_action(%{action: :run, params: %{x: 1}})
      "{:run, keys: [:x]}"
  """
  @spec format_action(term()) :: String.t()
  def format_action(nil), do: "nil"

  def format_action({action, params}) when is_atom(action) and is_map(params) do
    keys = params |> Map.keys() |> Enum.sort()
    "{#{inspect(action)}, keys: #{inspect(keys)}}"
  end

  def format_action({action, params}) when is_atom(action) and is_list(params) do
    "{#{inspect(action)}, arity: #{length(params)}}"
  end

  def format_action(%{action: action, params: params}) when is_map(params) do
    keys = params |> Map.keys() |> Enum.sort()
    "{#{inspect(action)}, keys: #{inspect(keys)}}"
  end

  def format_action(%{action: action}) do
    inspect(action)
  end

  def format_action(module) when is_atom(module) do
    case to_string(module) do
      "Elixir." <> rest -> rest
      other -> other
    end
  end

  def format_action(action) do
    safe_inspect(action, 60)
  end

  @doc """
  Inspect a term with a length limit.

  Safely inspects any term and truncates if necessary.

  ## Examples

      iex> Formatter.safe_inspect(%{a: 1, b: 2})
      "%{a: 1, b: 2}"

      iex> Formatter.safe_inspect(String.duplicate("x", 200), 50)
      "\\\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx..."
  """
  @spec safe_inspect(term(), pos_integer()) :: String.t()
  def safe_inspect(term, max_length \\ @default_max_length) do
    term
    |> inspect(limit: 10, printable_limit: max_length, width: max_length)
    |> truncate_string(max_length)
  rescue
    _ -> "<inspect_error>"
  end

  @doc """
  Extract just the keys from a map for safe logging.

  Useful when you want to log what fields are present without exposing values.

  ## Examples

      iex> Formatter.extract_keys(%{user_id: 123, secret: "password", data: %{}})
      [:data, :secret, :user_id]

      iex> Formatter.extract_keys(nil)
      []

      iex> Formatter.extract_keys("not a map")
      []
  """
  @spec extract_keys(map() | nil) :: list(atom() | String.t())
  def extract_keys(nil), do: []

  def extract_keys(map) when is_map(map) do
    map |> Map.keys() |> Enum.sort()
  end

  def extract_keys(_), do: []

  @doc """
  Format a complete log line with standard telemetry fields.

  Combines multiple formatting functions into a single log-ready string.

  ## Examples

      iex> Formatter.format_log_line(%{
      ...>   agent_id: "agent-1",
      ...>   trace_id: "trace-abc",
      ...>   signal_type: :user_request,
      ...>   duration: 1_500_000
      ...> })
      "agent_id=agent-1 duration=1.5ms signal_type=user_request trace_id=trace-abc"
  """
  @spec format_log_line(map()) :: String.t()
  def format_log_line(fields) when is_map(fields) do
    fields
    |> Enum.map(fn
      {:duration, v} -> {:duration, format_duration(v)}
      {:signal_type, v} -> {:signal_type, format_signal_type(v)}
      {k, v} -> {k, v}
    end)
    |> Map.new()
    |> format_metadata()
  end

  def format_log_line(_), do: ""
end
