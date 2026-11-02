defmodule Jido.Flow.DSL.ValueParser do
  @moduledoc false

  alias Jido.Expr
  alias Jido.Flow.Error
  alias Jido.Flow.Ref
  alias Jido.Flow.DSL.SourceMap

  @doc "Parses quoted fields in declaration order and keeps the first error location."
  @spec parse_fields(struct(), keyword(:value | :condition | {:value | :condition, term()})) ::
          {:ok, map()} | {:error, Exception.t()}
  def parse_fields(entity, fields) do
    Enum.reduce_while(fields, {:ok, %{}}, fn {field, kind}, {:ok, values} ->
      case parse_field(Map.fetch!(entity, field), kind) do
        {:ok, value} -> {:cont, {:ok, Map.put(values, field, value)}}
        {:error, error} -> {:halt, {:error, SourceMap.attach_entity(error, entity)}}
      end
    end)
  end

  defp parse_field(nil, {_kind, default}), do: {:ok, default}
  defp parse_field(value, {kind, _default}), do: parse_field(value, kind)
  defp parse_field(value, :value), do: parse(value)
  defp parse_field(value, :condition), do: parse_condition(value)

  @doc "Parses one DSL value into canonical Flow data."
  @spec parse(term()) :: {:ok, term()} | {:error, Exception.t()}
  def parse(expression) do
    case parse_value(expression) do
      {:ok, value} ->
        {:ok, value}

      {:error, %Expr.Error{reason: :duplicate_key}} ->
        {:error, Error.validation_error("duplicate Flow map key", source_details(expression))}

      {:error, error} ->
        {:error, Error.validation_error(expression_message(expression, error), source_details(expression))}
    end
  end

  # Plain Flow data keeps its existing limits. Only operation subtrees use
  # the shared expression budget; the operator grammar still has one owner.
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

  # Elixir quotes `-1` as unary minus. Keep it a literal, as data definitions do.
  defp parse_value({:-, _meta, [number]}) when is_number(number), do: {:ok, -number}

  defp parse_value(value) do
    case direct_leaf(value) do
      {:ok, leaf} -> {:ok, leaf}
      :error -> Expr.parse(value, leaf_parser: &parse_leaf/1)
      {:error, error} -> {:error, error}
    end
  end

  defp direct_leaf(value) do
    parse_leaf(value)
  rescue
    _error -> {:error, %Expr.Error{reason: :unsupported_syntax}}
  catch
    _, _ -> {:error, %Expr.Error{reason: :unsupported_syntax}}
  end

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

  @doc "Parses one DSL condition into canonical Flow data."
  @spec parse_condition(term()) ::
          {:ok, boolean() | Ref.t() | Expr.t()} | {:error, Exception.t()}
  def parse_condition(condition) do
    with {:ok, value} <- parse(condition) do
      case Jido.Flow.Value.condition(value, :any) do
        {:ok, value} ->
          {:ok, value}

        {:error, _error} ->
          {:error,
           Error.validation_error(
             "unsupported Flow condition: #{source_text(condition)}; " <>
               "use a Boolean reference, Boolean literal, or Jido.Expr operation",
             source_details(condition)
           )}
      end
    end
  end

  defp parse_leaf(%Ref{} = ref), do: {:ok, ref}
  defp parse_leaf({:input, _, []}), do: {:ok, Ref.input([])}
  defp parse_leaf({:input, _, [path]}), do: {:ok, Ref.input(parse_path!(path))}
  defp parse_leaf({:context, _, []}), do: {:ok, Ref.context([])}
  defp parse_leaf({:context, _, [path]}), do: {:ok, Ref.context(parse_path!(path))}

  defp parse_leaf({:value, _, [value]}), do: {:ok, literal!(value, true)}
  defp parse_leaf({:result, _, [name]}), do: {:ok, Ref.result(node_name!(name))}

  defp parse_leaf({:result, _, [name, path]}),
    do: {:ok, Ref.result(node_name!(name), parse_path!(path))}

  defp parse_leaf({:select, _, [source, path]}) do
    case parse(source) do
      {:ok, %Ref{} = ref} ->
        {:ok, %{ref | path: ref.path ++ Ref.normalize_path(parse_path!(path))}}

      _ ->
        :error
    end
  end

  defp parse_leaf({:item, _, []}), do: {:ok, Ref.item()}
  defp parse_leaf({:item, _, [path]}), do: {:ok, Ref.item(parse_path!(path))}
  defp parse_leaf({:item_index, _, []}), do: {:ok, Ref.item_index()}
  defp parse_leaf({:item_id, _, []}), do: {:ok, Ref.item_id()}
  defp parse_leaf({:accumulator, _, []}), do: {:ok, Ref.accumulator()}
  defp parse_leaf({:accumulator, _, [path]}), do: {:ok, Ref.accumulator(parse_path!(path))}
  defp parse_leaf({:state, _, []}), do: {:ok, Ref.state()}
  defp parse_leaf({:state, _, [path]}), do: {:ok, Ref.state(parse_path!(path))}
  defp parse_leaf({:iteration_index, _, []}), do: {:ok, Ref.iteration_index()}
  defp parse_leaf({:body_result, _, []}), do: {:ok, Ref.body_result()}
  defp parse_leaf({:body_result, _, [path]}), do: {:ok, Ref.body_result(parse_path!(path))}
  defp parse_leaf(_), do: :error

  defp node_name!(value) when is_binary(value) or (is_atom(value) and not is_nil(value)),
    do: value

  defp node_name!(_), do: raise(ArgumentError, "invalid result name")
  defp parse_path!(value) when is_atom(value) or is_binary(value) or is_integer(value), do: value
  defp parse_path!(value) when is_list(value), do: Enum.map(value, &literal!/1)
  defp parse_path!(_), do: raise(ArgumentError, "invalid reference path")
  defp literal!(value, negative_numbers? \\ false)

  defp literal!(value, _negative_numbers?)
       when is_atom(value) or is_binary(value) or is_number(value),
       do: value

  defp literal!({:-, _, [value]}, true) when is_number(value), do: -value

  defp literal!(values, negative_numbers?) when is_list(values),
    do: Enum.map(values, &literal!(&1, negative_numbers?))

  defp literal!({:%{}, _, pairs}, negative_numbers?) do
    if length(Enum.uniq_by(pairs, &elem(&1, 0))) != length(pairs),
      do: raise(ArgumentError, "duplicate Flow map key")

    Map.new(pairs, fn {key, value} -> {literal!(key), literal!(value, negative_numbers?)} end)
  end

  defp literal!(_, _negative_numbers?), do: raise(ArgumentError, "invalid literal")

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

  defp source_details(_), do: %{}
end
