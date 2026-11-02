defmodule Jido.Action.Output do
  @moduledoc """
  Explicit envelope for successful Action outputs that are not normal maps.

  Normal Action success values are map-shaped and validated by the Action's
  `output_schema`. Use this envelope only when a successful Action must return
  a raw, stream, batch, opaque, or shape-preserved value intentionally.

      Jido.Action.Output.raw("complete")
      Jido.Action.Output.batch([%{id: 1}, %{id: 2}])
      Jido.Action.Output.stream(Stream.map(1..3, & &1))
      Jido.Action.Output.opaque(reference, meta: %{owner: "worker"})

  Effects are optional and separate from the output value:

      {:ok, Jido.Action.Output.stream(stream)}
      {:ok, Jido.Action.Output.stream(stream), requests}

  `requests` is a proper list of effects for the caller. Exec does not consume
  the stream or dispatch the requests. Output metadata is data, not effects.
  """

  alias Jido.Action.Error

  @kinds [:raw, :stream, :batch, :opaque, :preserve]

  @schema Zoi.struct(
            __MODULE__,
            %{
              kind: Zoi.enum(@kinds, description: "Explicit output kind"),
              value: Zoi.any(description: "Explicit output value"),
              meta: Zoi.map(description: "Output metadata") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type kind :: :raw | :stream | :batch | :opaque | :preserve
  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc """
  Builds an explicit raw output envelope.
  """
  @spec raw(term(), keyword()) :: t()
  def raw(value, opts \\ []), do: build!(:raw, value, opts)

  @doc """
  Builds an explicit stream output envelope.
  """
  @spec stream(Enumerable.t(), keyword()) :: t()
  def stream(enumerable, opts \\ []), do: build!(:stream, enumerable, opts)

  @doc """
  Builds an explicit batch output envelope.
  """
  @spec batch(list(), keyword()) :: t()
  def batch(values, opts \\ []), do: build!(:batch, values, opts)

  @doc """
  Builds an explicit opaque output envelope.
  """
  @spec opaque(term(), keyword()) :: t()
  def opaque(value, opts \\ []), do: build!(:opaque, value, opts)

  @doc """
  Builds an output that applies the output schema and keeps its root shape.
  """
  @spec preserve(term(), keyword()) :: t()
  def preserve(value, opts \\ []), do: build!(:preserve, value, opts)

  @doc false
  @spec validate(term()) :: {:ok, t()} | {:error, Error.InvalidInputError.t()}
  def validate(%__MODULE__{} = output) do
    output
    |> Map.from_struct()
    |> parse()
    |> validate_kind_value(output)
  end

  def validate(output), do: invalid(output)

  defp build!(kind, value, opts) do
    meta = meta_opts!(opts)

    case validate(%__MODULE__{kind: kind, value: value, meta: meta}) do
      {:ok, output} ->
        output

      {:error, error} ->
        raise ArgumentError, Exception.message(error)
    end
  end

  defp meta_opts!(opts) when is_list(opts) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError, "invalid action output envelope"
    end

    {meta, opts} = Keyword.pop(opts, :meta, %{})

    if opts != [] do
      raise ArgumentError, "invalid action output envelope"
    end

    meta
  end

  defp meta_opts!(_opts), do: raise(ArgumentError, "invalid action output envelope")

  defp parse(attrs) do
    Zoi.parse(@schema, attrs)
  end

  defp validate_kind_value({:ok, %__MODULE__{kind: :stream, value: value} = output}, original) do
    if Enumerable.impl_for(value) && (not is_list(value) || proper_list?(value)) do
      {:ok, output}
    else
      invalid(original)
    end
  end

  defp validate_kind_value({:ok, %__MODULE__{kind: :batch, value: value} = output}, original) do
    if proper_list?(value) do
      {:ok, output}
    else
      invalid(original)
    end
  end

  defp validate_kind_value({:ok, %__MODULE__{} = output}, _original), do: {:ok, output}
  defp validate_kind_value({:error, _errors}, original), do: invalid(original)

  defp proper_list?([]), do: true
  defp proper_list?([_head | tail]), do: proper_list?(tail)
  defp proper_list?(_value), do: false

  defp invalid(value) do
    {:error,
     Error.validation_error("invalid action output envelope", %{
       value: value
     })}
  end
end
