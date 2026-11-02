defmodule Jido.Flow.Defaults do
  alias Jido.Joi
  @moduledoc false

  alias Jido.Flow.Error

  @doc false
  @spec normalize(term(), module()) ::
          {:ok, map()} | {:error, Error.InvalidDefinitionError.t()}
  def normalize(defaults, target) do
    with :ok <- map(defaults),
         {:ok, schema} <- flow_schema(target),
         {:ok, fields} <- schema_fields(schema),
         {:ok, defaults} <- normalize_fields(defaults, fields),
         :ok <- portable(defaults, []) do
      {:ok, defaults}
    end
  end

  @doc false
  @spec encode(term(), module()) ::
          {:ok, map()} | {:error, Error.InvalidDefinitionError.t()}
  def encode(defaults, target) do
    with {:ok, defaults} <- normalize(defaults, target) do
      json(defaults, [])
    end
  end

  @doc false
  @spec decode(term(), module()) ::
          {:ok, map()} | {:error, Error.InvalidDefinitionError.t()}
  def decode(defaults, target) do
    with :ok <- map(defaults),
         {:ok, schema} <- flow_schema(target),
         {:ok, fields} <- schema_fields(schema),
         {:ok, defaults} <- decode_fields(defaults, fields) do
      normalize(defaults, target)
    end
  end

  defp map(value) when is_map(value) and not is_struct(value), do: :ok
  defp map(_value), do: failure(:invalid_defaults, [], "Flow defaults must be a map")

  defp flow_schema(target) when is_atom(target) and target not in [nil, true, false] do
    case Jido.Instruction.resolve(target) do
      {:ok, %{kind: :flow}} -> {:ok, target.schema()}
      _other -> failure(:invalid_target, [], "Flow defaults require a Flow module")
    end
  rescue
    _error -> failure(:invalid_target, [], "Flow defaults require a Flow module")
  catch
    _kind, _reason -> failure(:invalid_target, [], "Flow defaults require a Flow module")
  end

  defp flow_schema(_target),
    do: failure(:invalid_target, [], "Flow defaults require a Flow module")

  defp schema_fields(schema) do
    case {Joi.Schema.kind(schema), Joi.Schema.fields(schema)} do
      {:map, {:ok, fields}} when is_list(fields) and fields != [] -> {:ok, fields}
      {:map, {:ok, fields}} when fields in [nil, []] -> {:ok, :open}
      _ -> failure(:invalid_schema, [], "Flow defaults require an object input schema")
    end
  end

  defp normalize_fields(defaults, :open), do: {:ok, defaults}

  defp normalize_fields(defaults, fields) do
    names = Map.new(fields, fn {key, schema} -> {to_string(key), {key, schema}} end)

    if map_size(names) == length(fields) do
      Enum.reduce_while(defaults, {:ok, %{}}, &normalize_field(&1, &2, names))
    else
      failure(
        :ambiguous_schema,
        [],
        "Flow input schema contains ambiguous field names"
      )
    end
  end

  defp normalize_field({key, value}, {:ok, normalized}, fields) do
    name = if is_atom(key) or is_binary(key), do: to_string(key)

    with true <- not is_nil(name),
         {:ok, {canonical, schema}} <- Map.fetch(fields, name),
         false <- Map.has_key?(normalized, canonical),
         {:ok, value} <- parse(schema, value, [canonical]) do
      {:cont, {:ok, Map.put(normalized, canonical, value)}}
    else
      false when is_nil(name) ->
        {:halt, failure(:invalid_field, [field_path(key)], "Flow default field is invalid")}

      :error ->
        {:halt, failure(:unknown_field, [field_path(key)], "Flow default field is unknown")}

      true ->
        {:halt, failure(:duplicate_field, [name], "Flow default field is present more than once")}

      {:error, _error} = error ->
        {:halt, error}
    end
  end

  defp decode_fields(defaults, :open), do: {:ok, defaults}

  defp decode_fields(defaults, fields) do
    schemas = Map.new(fields, fn {key, schema} -> {to_string(key), schema} end)

    {:ok,
     Map.new(defaults, fn {key, value} ->
       schema = if is_atom(key) or is_binary(key), do: Map.get(schemas, to_string(key))
       {key, restore_schema_atoms(schema, value)}
     end)}
  end

  defp restore_schema_atoms(schema, value) do
    case Joi.Schema.kind(schema) do
      :enum -> restore_enum_atom(schema, value)
      :atom -> restore_atom(value)
      :map -> restore_map_atoms(schema, value)
      :array -> restore_array_atoms(schema, value)
      :union -> restore_union_atoms(schema, value)
      _ -> value
    end
  end

  defp restore_enum_atom(schema, value) when is_binary(value) do
    with {:ok, :atom, values} <- Joi.Schema.enum(schema) do
      Enum.find_value(values, value, fn {_name, atom} ->
        if Atom.to_string(atom) == value, do: atom
      end)
    else
      _ -> value
    end
  end

  defp restore_enum_atom(_schema, value), do: value

  defp restore_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp restore_atom(value), do: value

  defp restore_map_atoms(schema, value) when is_map(value) and not is_struct(value) do
    {:ok, fields} = Joi.Schema.fields(schema)

    if is_list(fields) do
      schemas = Map.new(fields, fn {key, schema} -> {to_string(key), schema} end)

      Map.new(value, fn {key, item} ->
        schema = if is_atom(key) or is_binary(key), do: Map.get(schemas, to_string(key))
        {key, restore_schema_atoms(schema, item)}
      end)
    else
      value
    end
  end

  defp restore_map_atoms(_schema, value), do: value

  defp restore_array_atoms(schema, value) when is_list(value) do
    {:ok, inner} = Joi.Schema.inner(schema)
    Enum.map(value, &restore_schema_atoms(inner, &1))
  end

  defp restore_array_atoms(_schema, value), do: value

  defp restore_union_atoms(schema, value) do
    {:ok, schemas} = Joi.Schema.branches(schema)

    Enum.find_value(schemas, value, fn schema ->
      restored = restore_schema_atoms(schema, value)

      if restored !== value and match?({:ok, _value}, Joi.parse(schema, restored, coerce: true)),
        do: restored
    end)
  end

  defp parse(schema, value, path) do
    case Joi.parse(schema, value, coerce: true) do
      {:ok, normalized} ->
        {:ok, normalized}

      {:error, [error | _] = errors} ->
        error_path = Enum.map(Map.get(error, :path, []), &field_path/1)

        failure(
          :invalid_value,
          path ++ error_path,
          "Flow default does not match its input schema",
          %{errors: Enum.map(errors, &Map.take(&1, [:path, :message, :code]))}
        )

      {:error, reason} ->
        failure(:invalid_value, path, "Flow default does not match its input schema", %{
          reason: inspect(reason)
        })
    end
  rescue
    error ->
      failure(:invalid_value, path, "Flow default validation failed", %{
        reason: Exception.message(error)
      })
  catch
    kind, reason ->
      failure(:invalid_value, path, "Flow default validation failed", %{
        failure_kind: kind,
        reason: inspect(reason)
      })
  end

  defp portable(value, _path)
       when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value) or
              is_atom(value),
       do: :ok

  defp portable(value, path) when is_list(value) do
    if List.improper?(value) do
      failure(:non_portable_default, path, "Flow defaults must contain portable data")
    else
      value
      |> Enum.with_index()
      |> Enum.reduce_while(:ok, fn {item, index}, :ok ->
        case portable(item, path ++ [index]) do
          :ok -> {:cont, :ok}
          {:error, _error} = error -> {:halt, error}
        end
      end)
    end
  end

  defp portable(value, path) when is_map(value) and not is_struct(value) do
    value
    |> Enum.sort_by(fn {key, _item} -> :erlang.term_to_binary(key) end)
    |> Enum.reduce_while(:ok, fn {key, item}, :ok ->
      if is_atom(key) or is_binary(key) do
        case portable(item, path ++ [field_path(key)]) do
          :ok -> {:cont, :ok}
          {:error, _error} = error -> {:halt, error}
        end
      else
        {:halt,
         failure(
           :non_portable_default,
           path ++ [field_path(key)],
           "Flow default map keys must be atoms or strings"
         )}
      end
    end)
  end

  defp portable(_value, path),
    do: failure(:non_portable_default, path, "Flow defaults must contain portable data")

  defp json(value, _path)
       when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value),
       do: {:ok, value}

  defp json(value, _path) when is_atom(value), do: {:ok, Atom.to_string(value)}

  defp json(value, path) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, encoded} ->
      case json(item, path ++ [index]) do
        {:ok, item} -> {:cont, {:ok, [item | encoded]}}
        {:error, _error} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, encoded} -> {:ok, Enum.reverse(encoded)}
      error -> error
    end
  end

  defp json(value, path) when is_map(value) and not is_struct(value) do
    value
    |> Enum.sort_by(fn {key, _item} -> :erlang.term_to_binary(key) end)
    |> Enum.reduce_while({:ok, %{}}, fn {key, item}, {:ok, encoded} ->
      name = if is_atom(key) or is_binary(key), do: to_string(key)

      cond do
        is_nil(name) ->
          {:halt,
           failure(
             :non_portable_default,
             path ++ [field_path(key)],
             "Flow default map keys must be atoms or strings"
           )}

        Map.has_key?(encoded, name) ->
          {:halt,
           failure(
             :duplicate_field,
             path ++ [name],
             "Flow default field is present more than once"
           )}

        true ->
          case json(item, path ++ [name]) do
            {:ok, item} -> {:cont, {:ok, Map.put(encoded, name, item)}}
            {:error, _error} = error -> {:halt, error}
          end
      end
    end)
  end

  defp field_path(key) when is_atom(key) or is_binary(key), do: key
  defp field_path(key), do: inspect(key, limit: 10, printable_limit: 100)

  defp failure(code, path, message, details \\ %{}) do
    {:error,
     Error.validation_error(
       message,
       details
       |> Map.put(:code, code)
       |> Map.put(:path, path)
     )}
  end
end
