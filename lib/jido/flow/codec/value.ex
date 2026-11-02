defmodule Jido.Flow.Codec.Value do
  @moduledoc false
  alias Jido.Authoring.Registry.Error, as: AuthoringRegistryError
  alias Jido.Authoring.Value, as: AuthoringValue
  alias Jido.Authoring.Value.Error, as: AuthoringValueError
  alias Jido.Expr
  alias Jido.Flow.{Error, Ref, Value}
  alias Jido.Flow.Codec.Limits

  @doc false
  @spec encode_expression(term(), Jido.Authoring.Registry.t(), non_neg_integer()) ::
          {:ok, term()} | {:error, Exception.t()}
  def encode_expression(%Expr{} = expression, registry, depth) do
    with :ok <- Limits.depth(depth),
         {:ok, operands} <-
           encode_list(expression.operands, registry, depth + 1, &encode_expression/3) do
      {:ok,
       %{"$expr" => %{"operator" => Atom.to_string(expression.operator), "operands" => operands}}}
    end
  end

  def encode_expression(%Ref{} = ref, registry, depth) do
    with :ok <- Limits.depth(depth),
         {:ok, path} <- encode_list(ref.path, registry, depth + 1, &encode_data/3) do
      {:ok,
       %{
         "$ref" => %{
           "source" => Atom.to_string(ref.source),
           "step" => ref.step,
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
  @spec encode_data(term(), Jido.Authoring.Registry.t(), non_neg_integer()) ::
          {:ok, term()} | {:error, Exception.t()}
  def encode_data(value, %Jido.Authoring.Registry{} = registry, depth) do
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
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  @doc false
  @spec decode(term(), Jido.Authoring.Registry.t(), list(), :expression | :data) ::
          {:ok, term()} | {:error, [Exception.t()]}
  def decode(value, registry, stored, mode \\ :expression),
    do: decode(value, registry, stored, mode, 0)

  defp decode(value, _registry, _stored, _mode, _depth)
       when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value),
       do: {:ok, value}

  defp decode(values, registry, stored, mode, depth) when is_list(values) do
    case Limits.depth(depth) do
      :ok ->
        sequence(
          values,
          fn value, index ->
            decode(value, registry, stored ++ [index], mode, depth + 1)
          end
        )

      {:error, error} ->
        {:error, [Error.prefix_path(error, stored)]}
    end
  end

  defp decode(%{"$type" => "atom"} = record, registry, stored, _mode, _depth) do
    errors = unknown(record, ["$type", "id", "vsn"], stored)
    atom_record = Map.take(record, ["$type", "id", "vsn"])

    case AuthoringValue.decode(atom_record, registry) |> authoring_result() do
      {:ok, atom} when errors == [] ->
        {:ok, atom}

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

  defp decode(%{"$type" => "map"} = record, registry, stored, mode, depth) do
    errors = unknown(record, ["$type", "entries"], stored)

    case Map.get(record, "entries") do
      entries when is_list(entries) ->
        {map, errors} =
          entries
          |> Enum.with_index()
          |> Enum.reduce({%{}, Enum.reverse(errors)}, fn {entry, index}, {map, errors} ->
            entry_path = stored ++ ["entries", index]

            case decode_entry(entry, registry, entry_path, mode, depth) do
              {:ok, {key, value}} ->
                if Map.has_key?(map, key) do
                  {map,
                   [
                     Error.validation_error("stored map contains a duplicate key", %{
                       path: entry_path ++ ["key"]
                     })
                     | errors
                   ]}
                else
                  {Map.put(map, key, value), errors}
                end

              {:error, nested} ->
                {map, Enum.reverse(nested, errors)}
            end
          end)

        if errors == [], do: {:ok, map}, else: {:error, Enum.reverse(errors)}

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

  defp decode(%{"$ref" => record} = outer, registry, stored, :expression, depth)
       when is_map(record) and not is_struct(record) do
    errors =
      unknown(outer, ["$ref"], stored) ++
        unknown(record, ["source", "step", "path"], stored ++ ["$ref"])

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
      if is_nil(Map.get(record, "step")) or is_binary(Map.get(record, "step")),
        do: errors,
        else:
          errors ++
            [
              Error.validation_error("stored reference Step must be a string", %{
                path: stored ++ ["$ref", "step"]
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
                :data,
                depth + 1
              )
            end
          )

        case result do
          {:ok, path} when errors == [] ->
            {:ok, %Ref{source: source, step: Map.get(record, "step"), path: path}}

          {:ok, _path} ->
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

  defp decode(%{"$expr" => record} = outer, registry, stored, :expression, depth)
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
                   :expression,
                   depth + 1
                 )
               end
             ) do
          {:ok, operands} when errors == [] ->
            {:ok, %Expr{operator: elem(operator, 0), operands: operands}}

          {:ok, _operands} ->
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

  defp decode(_value, _registry, stored, _mode, _depth),
    do:
      {:error,
       [Error.validation_error("stored Flow data has an invalid tagged value", %{path: stored})]}

  defp decode_entry(
         %{"key" => key, "value" => value} = entry,
         registry,
         stored,
         mode,
         depth
       ) do
    errors = unknown(entry, ["key", "value"], stored)

    case decode(key, registry, stored ++ ["key"], :data, depth + 1) do
      {:ok, key} ->
        case Value.validate_key(key) do
          :ok ->
            case decode(value, registry, stored ++ ["value"], mode, depth + 1) do
              {:ok, value} when errors == [] -> {:ok, {key, value}}
              {:ok, _value} -> {:error, errors}
              {:error, nested} -> {:error, errors ++ nested}
            end

          {:error, error} ->
            {:error, errors ++ [Error.prefix_path(error, stored ++ ["key"])]}
        end

      {:error, nested} ->
        {:error, errors ++ nested}
    end
  end

  defp decode_entry(_entry, _registry, stored, _mode, _depth),
    do:
      {:error,
       [Error.validation_error("stored map entry must contain a key and value", %{path: stored})]}

  defp sequence(values, decoder) do
    {values, errors} =
      values
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {value, index}, {values, errors} ->
        case decoder.(value, index) do
          {:ok, value} -> {[value | values], errors}
          {:error, nested} -> {values, Enum.reverse(nested, errors)}
        end
      end)

    if errors == [], do: {:ok, Enum.reverse(values)}, else: {:error, Enum.reverse(errors)}
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

  defp authoring_result({:error, %AuthoringRegistryError{} = exception}) do
    message = String.replace(exception.message, "authoring Registry", "flow registry")
    {:error, Error.validation_error(message, exception.details)}
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
