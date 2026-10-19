defmodule Jido.Schema do
  @moduledoc false

  # Hex Zoi parses input. Jido additionally needs checked defaults at creation
  # and validation that cannot insert defaults or change committed values.
  alias Zoi.Types.Meta

  defmodule Node do
    @moduledoc false
    defstruct [:schema, :mode, :meta]
  end

  defimpl Zoi.Type, for: Node do
    def parse(node, input, _opts), do: Jido.Schema.parse(node.schema, input, node.mode)
  end

  def validate(schema, input) do
    case parse(schema, input, :stored) do
      {:ok, ^input} -> :ok
      {:ok, _changed} -> invalid("Validation cannot change stored values")
      {:error, _} = error -> error
    end
  end

  def parse(schema, input, mode) do
    input =
      if mode == :initialize and is_nil(input) and Meta.default?(schema.meta),
        do: Meta.default(schema.meta),
        else: input

    with {:ok, value} <- parse_type(schema, input, mode),
         do: refine(schema, value)
  end

  defp parse_type(%Zoi.Types.Intersection{schemas: [first | rest]}, input, mode) do
    with {:ok, first} <- parse(first, input, mode) do
      intersect(rest, first, input, mode)
    end
  end

  defp parse_type(schema, input, mode) do
    prepared =
      schema
      |> Map.from_struct()
      |> Map.new(fn
        {:meta, meta} ->
          {:meta, %{meta | default: nil, effects: []}}

        {:empty_values, _} ->
          {:empty_values, []}

        {key, value}
        when key in [:fields, :key_type, :value_type, :inner, :schemas, :unrecognized_keys] ->
          {key, children(value, mode)}

        entry ->
          entry
      end)
      |> then(&struct!(schema.__struct__, &1))

    Zoi.parse(prepared, defaults(schema, input, mode))
  end

  defp intersect(schemas, first, input, mode) do
    Enum.reduce_while(schemas, {:ok, first}, fn schema, {:ok, previous} ->
      with {:ok, value} <- parse(schema, input, mode),
           {:ok, merged} <- merge(previous, value) do
        {:cont, {:ok, merged}}
      else
        error -> {:halt, error}
      end
    end)
  end

  # Wrap child schemas so Hex Zoi retains container parsing and error paths,
  # while each child passes through the same Jido rules exactly once.
  defp children(%{meta: %Meta{}} = schema, mode) do
    required =
      if Meta.default?(schema.meta) and schema.meta.required != false,
        do: true,
        else: schema.meta.required

    %Node{schema: schema, mode: mode, meta: %Meta{required: required}}
  end

  defp children(list, mode) when is_list(list), do: Enum.map(list, &children(&1, mode))

  defp children(tuple, mode) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&children(&1, mode)) |> List.to_tuple()

  defp children(map, mode) when is_map(map) and not is_struct(map),
    do: Map.new(map, fn {key, value} -> {key, children(value, mode)} end)

  defp children(value, _mode), do: value

  defp defaults(%{fields: fields} = schema, input, :initialize)
       when is_list(fields) and is_map(input) do
    Enum.reduce(fields, input, fn {key, child}, acc ->
      acc =
        if Map.get(acc, key) in Map.get(schema, :empty_values, []),
          do: Map.delete(acc, key),
          else: acc

      if not Map.has_key?(acc, key) and child.meta.required != false and
           Meta.default?(child.meta),
         do: Map.put(acc, key, Meta.default(child.meta)),
         else: acc
    end)
  end

  defp defaults(%Zoi.Types.Keyword{fields: fields} = schema, input, :initialize)
       when is_list(fields) and is_list(input) do
    if Keyword.keyword?(input),
      do: schema |> defaults(Map.new(input), :initialize) |> Map.to_list(),
      else: input
  end

  defp defaults(_schema, input, _mode), do: input

  defp refine(schema, value) do
    Enum.reduce_while(schema.meta.effects, {:ok, value}, fn effect, {:ok, value} ->
      context = %Zoi.Context{
        schema: %{schema | meta: %{schema.meta | effects: [effect]}},
        input: value,
        parsed: value,
        valid?: true
      }

      case Meta.run_effects(context) do
        {:ok, %{parsed: ^value}} -> {:cont, {:ok, value}}
        {:ok, _changed} -> {:halt, invalid("State refinements cannot change values")}
        {:error, context} -> {:halt, {:error, context.errors}}
      end
    end)
  end

  defp merge(left, right) when left === right, do: {:ok, left}

  defp merge(left, right)
       when is_map(left) and not is_struct(left) and is_map(right) and not is_struct(right) do
    Enum.reduce_while(right, {:ok, left}, fn {key, value}, {:ok, acc} ->
      case Map.fetch(acc, key) do
        :error ->
          {:cont, {:ok, Map.put(acc, key, value)}}

        {:ok, previous} ->
          case merge(previous, value) do
            {:ok, merged} ->
              {:cont, {:ok, Map.put(acc, key, merged)}}

            {:error, errors} ->
              {:halt, {:error, Enum.map(errors, &Zoi.Error.prepend_path(&1, [key]))}}
          end
      end
    end)
  end

  defp merge(_left, _right), do: invalid("Intersection branches produced conflicting values")

  defp invalid(message), do: {:error, [Zoi.Error.custom_error(issue: {message, []})]}
end
