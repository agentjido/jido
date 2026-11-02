defmodule Jido.Signal.Router.Route do
  @moduledoc """
  A validated Signal routing rule.

  `path` selects Signal types. `target` is any value returned by the Router.
  `priority` orders routes with equal path specificity. An optional `match`
  predicate can inspect the full Signal after the path matches. Runtime
  routers accept a unary function. Compiled routers accept only a
  `{module, function, args}` MFA.
  """

  alias Jido.Signal

  @schema Zoi.struct(
            __MODULE__,
            %{
              path:
                Zoi.any()
                |> Zoi.refine({__MODULE__, :validate_path, []}),
              target: Zoi.any(),
              priority:
                Zoi.any()
                |> Zoi.refine({__MODULE__, :validate_priority, []})
                |> Zoi.default(0)
                |> Zoi.optional(),
              match:
                Zoi.any()
                |> Zoi.refine({__MODULE__, :validate_match, []})
                |> Zoi.nullable()
                |> Zoi.optional()
            }
          )

  @type match :: (Signal.t() -> boolean()) | {module(), atom(), list()}

  @type t :: %__MODULE__{
          path: String.t(),
          target: term(),
          priority: -100..100,
          match: nil | match()
        }

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for a Route."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc false
  def validate_path(path, _opts) when not is_binary(path),
    do: {:error, "Path must be a string"}

  def validate_path(path, _opts) do
    segments = String.split(path, ".")

    cond do
      String.contains?(path, "..") ->
        {:error, "Path cannot contain consecutive dots"}

      consecutive_multi_wildcards?(segments) ->
        {:error, "Path cannot contain multiple wildcards"}

      invalid = Enum.find(segments, &(not valid_segment?(&1))) ->
        invalid_segment_error(invalid)

      true ->
        :ok
    end
  end

  @doc false
  def validate_priority(nil, _opts), do: :ok

  def validate_priority(priority, _opts) when is_integer(priority) and priority > 100,
    do: {:error, "Priority value exceeds maximum allowed"}

  def validate_priority(priority, _opts) when is_integer(priority) and priority < -100,
    do: {:error, "Priority value below minimum allowed"}

  def validate_priority(priority, _opts) when is_integer(priority), do: :ok
  def validate_priority(_priority, _opts), do: {:error, "Priority must be an integer"}

  @doc false
  def validate_match(nil, _opts), do: :ok
  def validate_match(match, _opts) when is_function(match, 1), do: :ok

  def validate_match({module, function, args}, _opts)
      when is_atom(module) and is_atom(function) and is_list(args),
      do: :ok

  def validate_match(_match, _opts),
    do: {:error, "Match must be a unary function or a {module, function, args} MFA"}

  @doc false
  @spec matched?(nil | match(), Signal.t()) :: boolean()
  def matched?(nil, _signal), do: true

  def matched?(match, signal) when is_function(match, 1), do: match.(signal) == true

  def matched?({module, function, args}, signal)
      when is_atom(module) and is_atom(function) and is_list(args) do
    apply(module, function, [signal | args]) == true
  end

  defp consecutive_multi_wildcards?(["**", "**" | _rest]), do: true
  defp consecutive_multi_wildcards?([_segment | rest]), do: consecutive_multi_wildcards?(rest)
  defp consecutive_multi_wildcards?([]), do: false

  defp valid_segment?("*"), do: true
  defp valid_segment?("**"), do: true
  defp valid_segment?(segment), do: String.match?(segment, ~r/\A[a-zA-Z0-9_-]+\z/)

  defp invalid_segment_error(segment) do
    cond do
      String.contains?(segment, "**") ->
        {:error, "Path cannot contain '**' sequence"}

      String.contains?(segment, "*") ->
        {:error, "Path cannot contain '*' within a segment"}

      true ->
        {:error, "Path contains invalid characters"}
    end
  end
end
