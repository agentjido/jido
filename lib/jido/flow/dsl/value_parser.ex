defmodule Jido.Flow.DSL.ValueParser do
  @moduledoc false

  alias Jido.Expr
  alias Jido.Flow.{Error, Ref}
  alias Jido.Flow.DSL.SourceMap

  @doc false
  @spec parse_fields(struct(), keyword(:value)) :: {:ok, map()} | {:error, Exception.t()}
  def parse_fields(entity, fields) do
    Enum.reduce_while(fields, {:ok, %{}}, fn {field, :value}, {:ok, values} ->
      case parse(Map.fetch!(entity, field)) do
        {:ok, value} -> {:cont, {:ok, Map.put(values, field, value)}}
        {:error, error} -> {:halt, {:error, SourceMap.attach_entity(error, entity)}}
      end
    end)
  end

  @doc false
  @spec parse(term()) :: {:ok, term()} | {:error, Exception.t()}
  def parse(expression) do
    case parse_value(expression) do
      {:ok, value} ->
        {:ok, value}

      {:error, %Expr.Error{reason: :duplicate_key}} ->
        {:error, Error.validation_error("duplicate Flow map key", source_details(expression))}

      {:error, error} ->
        {:error,
         Error.validation_error(expression_message(expression, error), source_details(expression))}
    end
  end

  defp parse_value({:expr, _, [value]}), do: parse_value(value)

  defp parse_value({:%{}, _, pairs}) when is_list(pairs) do
    if List.improper?(pairs),
      do: {:error, %Expr.Error{reason: :improper_list}},
      else: parse_map(pairs, %{})
  end

  defp parse_value(value) when is_map(value) and not is_struct(value),
    do: parse_map(value, %{})

  defp parse_value(values) when is_list(values), do: parse_list(values, [])

  defp parse_value(value) when is_atom(value) or is_number(value) or is_binary(value),
    do: {:ok, value}

  defp parse_value({:-, _meta, [number]}) when is_number(number), do: {:ok, -number}

  defp parse_value(value) do
    case direct_leaf(value) do
      {:ok, leaf} -> {:ok, leaf}
      :error -> Expr.parse(value, leaf_parser: &parse_leaf/1)
      {:error, error} -> {:error, error}
    end
  end

  defp direct_leaf(value), do: parse_leaf(value)

  defp parse_list([], values), do: {:ok, Enum.reverse(values)}

  defp parse_list([head | tail], values) do
    with {:ok, value} <- parse_value(head), do: parse_list(tail, [value | values])
  end

  defp parse_list(_tail, _values), do: {:error, %Expr.Error{reason: :improper_list}}

  defp parse_map(pairs, values) do
    Enum.reduce_while(pairs, {:ok, values}, fn
      {key, value}, {:ok, values} when is_atom(key) or is_binary(key) or is_integer(key) ->
        if Map.has_key?(values, key) do
          {:halt, {:error, %Expr.Error{reason: :duplicate_key}}}
        else
          case parse_value(value) do
            {:ok, value} -> {:cont, {:ok, Map.put(values, key, value)}}
            {:error, error} -> {:halt, {:error, error}}
          end
        end

      _pair, _values ->
        {:halt, {:error, %Expr.Error{reason: :invalid_map_key}}}
    end)
  end

  defp parse_leaf(%Ref{} = ref), do: {:ok, ref}
  defp parse_leaf({:input, _, []}), do: {:ok, Ref.input([])}

  defp parse_leaf({:input, _, [path]}) do
    with {:ok, path} <- parse_path(path), do: {:ok, Ref.input(path)}
  end

  defp parse_leaf({:context, _, []}), do: {:ok, Ref.context([])}

  defp parse_leaf({:context, _, [path]}) do
    with {:ok, path} <- parse_path(path), do: {:ok, Ref.context(path)}
  end

  defp parse_leaf({:item, _, []}), do: {:ok, Ref.item([])}

  defp parse_leaf({:item, _, [path]}) do
    with {:ok, path} <- parse_path(path), do: {:ok, Ref.item(path)}
  end

  defp parse_leaf({:item_index, _, []}), do: {:ok, Ref.item_index()}
  defp parse_leaf({:accumulator, _, []}), do: {:ok, Ref.accumulator([])}

  defp parse_leaf({:accumulator, _, [path]}) do
    with {:ok, path} <- parse_path(path), do: {:ok, Ref.accumulator(path)}
  end

  defp parse_leaf({:state, _, []}), do: {:ok, Ref.state([])}

  defp parse_leaf({:state, _, [path]}) do
    with {:ok, path} <- parse_path(path), do: {:ok, Ref.state(path)}
  end

  defp parse_leaf({:iteration_index, _, []}), do: {:ok, Ref.iteration_index()}
  defp parse_leaf({:body_result, _, []}), do: {:ok, Ref.body_result([])}

  defp parse_leaf({:body_result, _, [path]}) do
    with {:ok, path} <- parse_path(path), do: {:ok, Ref.body_result(path)}
  end

  defp parse_leaf({:value, _, [value]}), do: literal(value, true)

  defp parse_leaf({:result, _, [name]}) do
    with {:ok, name} <- step_name(name), do: {:ok, Ref.result(name)}
  end

  defp parse_leaf({:result, _, [name, path]}) do
    with {:ok, name} <- step_name(name),
         {:ok, path} <- parse_path(path) do
      {:ok, Ref.result(name, path)}
    end
  end

  defp parse_leaf({:select, _, [source, path]}) do
    with {:ok, %Ref{} = ref} <- parse(source),
         {:ok, path} <- parse_path(path),
         selected = %{ref | path: ref.path ++ Ref.normalize_path(path)},
         :ok <- Ref.validate(selected, :any) do
      {:ok, selected}
    else
      _other -> :error
    end
  end

  defp parse_leaf(_value), do: :error

  defp step_name(value) do
    case Jido.Flow.DSL.Name.normalize(value) do
      {:ok, name} -> {:ok, name}
      {:error, _message} -> :error
    end
  end

  defp parse_path(value) when is_atom(value) or is_binary(value) or is_integer(value),
    do: {:ok, value}

  defp parse_path(value) when is_list(value), do: literal(value)
  defp parse_path(_value), do: :error

  defp literal(value, negative_numbers? \\ false)

  defp literal(value, _negative_numbers?)
       when is_atom(value) or is_binary(value) or is_number(value),
       do: {:ok, value}

  defp literal({:-, _, [value]}, true) when is_number(value), do: {:ok, -value}

  defp literal(values, negative_numbers?) when is_list(values),
    do: literal_list(values, negative_numbers?, [])

  defp literal({:%{}, _, pairs}, negative_numbers?) when is_list(pairs) do
    if List.improper?(pairs) do
      :error
    else
      Enum.reduce_while(pairs, {:ok, %{}}, fn
        {key, value}, {:ok, result} ->
          with {:ok, key} <- literal(key),
               false <- Map.has_key?(result, key),
               {:ok, value} <- literal(value, negative_numbers?) do
            {:cont, {:ok, Map.put(result, key, value)}}
          else
            true -> {:halt, {:error, %Expr.Error{reason: :duplicate_key}}}
            error -> {:halt, error}
          end

        _pair, _result ->
          {:halt, :error}
      end)
    end
  end

  defp literal(_value, _negative_numbers?), do: :error

  defp literal_list([], _negative_numbers?, values), do: {:ok, Enum.reverse(values)}

  defp literal_list([head | tail], negative_numbers?, values) do
    with {:ok, value} <- literal(head, negative_numbers?),
         do: literal_list(tail, negative_numbers?, [value | values])
  end

  defp literal_list(_tail, _negative_numbers?, _values), do: :error

  defp expression_message(_expression, %Expr.Error{reason: reason})
       when reason in [:max_depth, :max_nodes, :max_binary_bytes, :max_integer_bits],
       do: "Flow expression exceeds #{reason}"

  defp expression_message(expression, _error),
    do:
      "unsupported Flow expression: #{source_text(expression)}; " <>
        "use a Flow reference, literal, map, or list"

  defp source_text(expression) do
    Macro.to_string(expression)
  rescue
    _error -> "<invalid syntax>"
  end

  defp source_details({_form, metadata, _arguments}) when is_list(metadata),
    do: metadata |> Keyword.take([:line, :column]) |> Map.new()

  defp source_details(_expression), do: %{}
end
