defmodule Jido.Authoring.Issue do
  @moduledoc """
  Describes one authoring problem at a source JSON path.

  Codecs return Issues directly. Codes and paths are stable machine data.
  Messages explain the problem to a person.
  """

  @enforce_keys [:code, :path, :message]
  defstruct [:code, :path, :message, details: %{}]

  @type segment :: String.t() | non_neg_integer()
  @type t :: %__MODULE__{
          code: atom(),
          path: [segment()],
          message: String.t(),
          details: map()
        }

  @doc "Builds one issue with JSON-compatible public data."
  @spec new(atom(), [segment()], String.t(), keyword()) :: t()
  def new(code, path, message, opts \\ []) do
    issue = %__MODULE__{
      code: code,
      path: path,
      message: message,
      details: safe_details(Keyword.get(opts, :details, %{}))
    }

    if valid?(issue), do: issue, else: raise(ArgumentError, "invalid authoring issue")
  end

  @doc false
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{} = issue) do
    is_atom(issue.code) and issue.code not in [nil, true, false] and
      valid_path?(issue.path) and is_binary(issue.message) and String.valid?(issue.message) and
      is_map(issue.details) and json?(to_map(issue))
  end

  def valid?(_issue), do: false

  @doc "Converts one issue to JSON-compatible data."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = issue) do
    %{
      "code" => Atom.to_string(issue.code),
      "path" => issue.path,
      "message" => issue.message,
      "details" => issue.details
    }
  end

  defp safe_details(details) when is_map(details) do
    if json?(details),
      do: details,
      else: %{value: inspect(details, limit: 20, printable_limit: 1_000)}
  end

  defp safe_details(details),
    do: %{value: inspect(details, limit: 20, printable_limit: 1_000)}

  defp valid_path?(path) when is_list(path) do
    not List.improper?(path) and
      Enum.all?(path, fn
        segment when is_binary(segment) -> String.valid?(segment)
        segment when is_integer(segment) -> segment >= 0
        _segment -> false
      end)
  end

  defp valid_path?(_path), do: false

  defp json?(value) do
    match?({:ok, _json}, Jason.encode(value, maps: :strict))
  rescue
    _error -> false
  catch
    _kind, _reason -> false
  end
end
