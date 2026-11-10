defmodule Jido.Flow.Codec.Value do
  @moduledoc false
  alias Jido.Catalog
  alias Jido.Catalog.Error, as: CatalogError
  alias Jido.Codec.Value, as: AuthoringValue
  alias Jido.Codec.Value.Error, as: AuthoringValueError
  alias Jido.Expr
  alias Jido.Error
  alias Jido.Flow.{Ref, Value}
  alias Jido.Flow.Codec.{Limits, Paths}

  @doc false
  @spec encode_expression(term(), Catalog.t(), non_neg_integer()) ::
          {:ok, term()} | {:error, Exception.t()}
  def encode_expression(%Jido.Expr.Operation{} = expression, registry, depth) do
    with :ok <- Limits.depth(depth),
         {:ok, operands} <-
           encode_list(expression.operands, registry, depth + 1, &encode_expression/3) do
      {:ok, %{"$expr" => %{"operator" => Atom.to_string(expression.operator), "operands" => operands}}}
    end
  end

  def encode_expression(%Ref{} = ref, registry, depth) do
    with :ok <- Limits.depth(depth),
         {:ok, path} <- encode_list(ref.path, registry, depth + 1, &encode_data/3) do
      {:ok,
       %{
         "$ref" => %{
           "source" => Atom.to_string(ref.source),
           "component" => ref.component,
           "path" => path
         }
       }}
    end
  end

  def encode_expression(value, registry, depth) when is_list(value) do
    encode_list(value, registry, depth, &encode_expression/3)
  end

  def encode_expression(value, registry, depth) when is_map(value) and not is_struct(value) do
    encode_map(value, registry, depth, &encode_expression/3)
  end

  def encode_expression(value, registry, depth), do: encode_data(value, registry, depth)

  @doc false
  @spec encode_data(term(), Catalog.t(), non_neg_integer()) ::
          {:ok, term()} | {:error, Exception.t()}
  def encode_data(value, %Catalog{} = registry, depth) do
    with :ok <- Limits.depth(depth) do
      value
      |> AuthoringValue.encode(registry)
      |> authoring_result()
    end
  end

  defp encode_list(list, registry, depth, encoder) do
    with :ok <- Limits.depth(depth),
         :ok <- Limits.size(list) do
      list
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {value, index}, {:ok, encoded} ->
        case encoder.(value, registry, depth + 1) do
          {:ok, value} -> {:cont, {:ok, [value | encoded]}}
          {:error, error} -> {:halt, {:error, Error.prefix_path(error, [index])}}
        end
      end)
      |> reverse_ok()
    end
  end

  defp encode_map(map, registry, depth, value_encoder) do
    with :ok <- Limits.depth(depth),
         :ok <- Limits.size(map),
         {:ok, entries} <- encode_entries(map, registry, depth, value_encoder) do
      entries =
        Enum.sort_by(entries, fn %{"key" => key} ->
          AuthoringValue.encoded_key_sort_key(key)
        end)

      {:ok, %{"$type" => "map", "entries" => entries}}
    end
  end

  defp encode_entries(map, registry, depth, value_encoder) do
    Enum.reduce_while(map, {:ok, []}, fn {key, value}, {:ok, encoded} ->
      result =
        with {:ok, key} <- encode_data(key, registry, depth + 1),
             {:ok, value} <- value_encoder.(value, registry, depth + 1) do
          {:ok, %{"key" => key, "value" => value}}
        end

      case result do
        {:ok, entry} -> {:cont, {:ok, [entry | encoded]}}
        {:error, error} -> {:halt, {:error, Error.prefix_path(error, [key])}}
      end
    end)
  end

  @doc false
  @spec decode(term(), Catalog.t(), list(), list(), :expression | :data) ::
          {:ok, term(), Paths.t()} | {:error, [Exception.t()]}
  def decode(value, registry, stored, canonical, mode \\ :expression),
    do: decode(value, registry, stored, canonical, mode, 0)

  defp decode(value, _registry, stored, canonical, _mode, _depth)
       when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value),
       do: {:ok, value, %{canonical => stored}}

  defp decode(values, registry, stored, canonical, mode, depth) when is_list(values) do
    case Limits.depth(depth) do
      :ok ->
        sequence(
          values,
          fn value, index ->
            decode(value, registry, stored ++ [index], canonical ++ [index], mode, depth + 1)
          end,
          canonical,
          stored
        )

      {:error, error} ->
        {:error, [Error.prefix_path(error, stored)]}
    end
  end

  defp decode(%{"$type" => "atom"} = record, registry, stored, canonical, _mode, _depth) do
    errors = unknown(record, ["$type", "id", "vsn"], stored)
    atom_record = Map.take(record, ["$type", "id", "vsn"])

    case AuthoringValue.decode(atom_record, registry) |> authoring_result() do
      {:ok, atom} when errors == [] ->
        {:ok, atom, %{canonical => stored}}

      {:ok, _} ->
        {:error, errors}

      {:error, error} ->
        field =
          if Map.has_key?(record, "vsn"),
            do: reference_error_field(error),
            else: "id"

        {:error, errors ++ [Error.prefix_path(error, stored ++ [field])]}
    end
  end

  defp decode(%{"$type" => "map"} = record, registry, stored, canonical, mode, depth) do
    errors = unknown(record, ["$type", "entries"], stored)

    case Map.get(record, "entries") do
      entries when is_list(entries) ->
        {map, paths, errors} =
          entries
          |> Enum.with_index()
          |> Enum.reduce({%{}, %{canonical => stored}, Enum.reverse(errors)}, fn {entry, index}, {map, paths, errors} ->
            entry_path = stored ++ ["entries", index]

            case decode_entry(entry, registry, entry_path, canonical, mode, depth) do
              {:ok, {key, value}, nested_paths} ->
                if Map.has_key?(map, key) do
                  {map, paths,
                   [
                     Error.validation_error("stored map contains a duplicate key", %{
                       path: entry_path ++ ["key"]
                     })
                     | errors
                   ]}
                else
                  {Map.put(map, key, value), Map.merge(paths, nested_paths), errors}
                end

              {:error, nested} ->
                {map, paths, Enum.reverse(nested, errors)}
            end
          end)

        if errors == [], do: {:ok, map, paths}, else: {:error, Enum.reverse(errors)}

      _ ->
        {:error,
         errors ++
           [
             Error.validation_error("stored Flow field must be a list", %{
               path: stored ++ ["entries"]
             })
           ]}
    end
  end

  defp decode(%{"$ref" => record} = outer, registry, stored, canonical, :expression, depth)
       when is_map(record) and not is_struct(record) do
    errors =
      unknown(outer, ["$ref"], stored) ++
        unknown(record, ["source", "component", "path"], stored ++ ["$ref"])

    source = Enum.find(Ref.sources(), &(Atom.to_string(&1) == Map.get(record, "source")))

    errors =
      if source,
        do: errors,
        else:
          errors ++
            [
              Error.validation_error("stored Flow reference source is not supported", %{
                path: stored ++ ["$ref", "source"]
              })
            ]

    errors =
      if is_nil(Map.get(record, "component")) or is_binary(Map.get(record, "component")),
        do: errors,
        else:
          errors ++
            [
              Error.validation_error("stored reference component must be a string", %{
                path: stored ++ ["$ref", "component"]
              })
            ]

    case Map.get(record, "path") do
      path when is_list(path) ->
        result =
          sequence(
            path,
            fn value, index ->
              decode(
                value,
                registry,
                stored ++ ["$ref", "path", index],
                canonical ++ [:path, index],
                :data,
                depth + 1
              )
            end,
            canonical ++ [:path],
            stored ++ ["$ref", "path"]
          )

        case result do
          {:ok, path, paths} when errors == [] ->
            {:ok, %Ref{source: source, component: Map.get(record, "component"), path: path},
             Map.put(paths, canonical, stored)}

          {:ok, _, _} ->
            {:error, errors}

          {:error, nested} ->
            {:error, errors ++ nested}
        end

      _ ->
        {:error,
         errors ++
           [
             Error.validation_error("stored Flow data must be a list", %{
               path: stored ++ ["$ref", "path"]
             })
           ]}
    end
  end

  defp decode(%{"$expr" => record} = outer, registry, stored, canonical, :expression, depth)
       when is_map(record) and not is_struct(record) do
    errors =
      unknown(outer, ["$expr"], stored) ++
        unknown(record, ["operator", "operands"], stored ++ ["$expr"])

    operator =
      Enum.find(Expr.operations(), fn {op, _arity} ->
        Atom.to_string(op) == Map.get(record, "operator")
      end)

    errors =
      if operator,
        do: errors,
        else:
          errors ++
            [
              Error.validation_error("stored expression operator is not supported", %{
                path: stored ++ ["$expr", "operator"]
              })
            ]

    case Map.get(record, "operands") do
      values when is_list(values) ->
        case sequence(
               values,
               fn value, index ->
                 decode(
                   value,
                   registry,
                   stored ++ ["$expr", "operands", index],
                   canonical ++ [:operands, index],
                   :expression,
                   depth + 1
                 )
               end,
               canonical ++ [:operands],
               stored ++ ["$expr", "operands"]
             ) do
          {:ok, operands, paths} when errors == [] ->
            {:ok, %Jido.Expr.Operation{operator: elem(operator, 0), operands: operands},
             Map.put(paths, canonical, stored ++ ["$expr"])}

          {:ok, _, _} ->
            {:error, errors}

          {:error, nested} ->
            {:error, errors ++ nested}
        end

      _ ->
        {:error,
         errors ++
           [
             Error.validation_error("stored Flow data must be a list", %{
               path: stored ++ ["$expr", "operands"]
             })
           ]}
    end
  end

  defp decode(_value, _registry, stored, _canonical, _mode, _depth),
    do: {:error, [Error.validation_error("stored Flow data has an invalid tagged value", %{path: stored})]}

  defp decode_entry(
         %{"key" => key, "value" => value} = entry,
         registry,
         stored,
         canonical,
         mode,
         depth
       ) do
    errors = unknown(entry, ["key", "value"], stored)

    case decode(key, registry, stored ++ ["key"], [], :data, depth + 1) do
      {:ok, key, _paths} ->
        case Value.validate_key(key) do
          :ok ->
            case decode(value, registry, stored ++ ["value"], canonical ++ [key], mode, depth + 1) do
              {:ok, value, paths} when errors == [] -> {:ok, {key, value}, paths}
              {:ok, _, _} -> {:error, errors}
              {:error, nested} -> {:error, errors ++ nested}
            end

          {:error, error} ->
            {:error, errors ++ [Error.prefix_path(error, stored ++ ["key"])]}
        end

      {:error, nested} ->
        {:error, errors ++ nested}
    end
  end

  defp decode_entry(_entry, _registry, stored, _canonical, _mode, _depth),
    do: {:error, [Error.validation_error("stored map entry must contain a key and value", %{path: stored})]}

  defp sequence(values, decoder, canonical, stored) do
    {values, paths, errors} =
      values
      |> Enum.with_index()
      |> Enum.reduce({[], %{canonical => stored}, []}, fn {value, index}, {values, paths, errors} ->
        case decoder.(value, index) do
          {:ok, value, nested_paths} -> {[value | values], Map.merge(paths, nested_paths), errors}
          {:error, nested} -> {values, paths, Enum.reverse(nested, errors)}
        end
      end)

    if errors == [], do: {:ok, Enum.reverse(values), paths}, else: {:error, Enum.reverse(errors)}
  end

  defp unknown(record, fields, stored) do
    record
    |> Map.keys()
    |> Enum.reject(&(&1 in fields))
    |> Enum.sort()
    |> Enum.map(fn field ->
      Error.validation_error("unknown stored Flow field: #{inspect(field)}", %{
        path: stored ++ [field],
        field: field
      })
    end)
  end

  defp reverse_ok({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_ok(error), do: error

  defp reference_error_field(%{details: %{field: field}}) when is_binary(field), do: field
  defp reference_error_field(_error), do: "id"

  @doc false
  @spec catalog_error(CatalogError.t()) :: Exception.t()
  def catalog_error(%CatalogError{} = exception) do
    message = String.replace(exception.message, "Catalog", "flow catalog")
    Error.validation_error(message <> missing_target(exception.details), exception.details)
  end

  defp missing_target(%{target: target}), do: ": #{inspect(target)}"
  defp missing_target(_details), do: ""

  defp authoring_result({:error, %CatalogError{} = exception}) do
    {:error, catalog_error(exception)}
  end

  defp authoring_result({:error, %AuthoringValueError{} = exception}) do
    message =
      case exception.reason do
        :string -> "flow data strings must be valid UTF-8"
        :list -> "flow data must contain proper lists"
        :map_key -> "flow data contains an unsupported map key"
        :value -> "flow data contains an unsupported value"
        :depth -> "stored Flow exceeds its nesting limit"
        :collection -> "stored Flow collection exceeds its size limit"
        _ -> exception.message
      end

    details = Map.put(exception.details, :path, exception.path)
    {:error, Error.validation_error(message, details)}
  end

  defp authoring_result(result), do: result
end
