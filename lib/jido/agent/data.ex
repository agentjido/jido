defmodule Jido.Agent.Data do
  alias Jido.Joi
  @moduledoc false
  alias Jido.Agent.Error

  def fields(value, allowed, defaults \\ %{}) do
    with :ok <- plain_map(value),
         [] <- Map.keys(value) -- allowed do
      {:ok, Map.merge(defaults, value)}
    else
      keys when is_list(keys) -> Error.fail(:unknown_fields, [], "Unknown fields", %{keys: keys})
      error -> error
    end
  end

  def plain_map(value) when is_map(value) and not is_struct(value), do: :ok
  def plain_map(_), do: Error.fail(:invalid_map, [], "Expected a plain Map")

  def nonempty(value) when is_binary(value) and byte_size(value) > 0, do: :ok
  def nonempty(_), do: Error.fail(:invalid_string, [], "Expected a nonempty string")

  def name(value) when is_atom(value) and value not in [nil, true, false], do: :ok
  def name(_), do: Error.fail(:invalid_name, [], "Expected a name atom")

  def positive(value) when is_integer(value) and value > 0, do: :ok
  def positive(_), do: Error.fail(:invalid_positive, [], "Expected a positive integer")

  def list(values, fun), do: walk(values, fun, 0, [])
  defp walk([], _fun, _index, acc), do: {:ok, Enum.reverse(acc)}

  defp walk([value | tail], fun, index, acc) do
    with {:ok, value} <- Error.at(fun.(value), [index]),
         do: walk(tail, fun, index + 1, [value | acc])
  end

  defp walk(_, _, _, _), do: Error.fail(:invalid_list, [], "Expected a proper list")

  def unique(values, key) do
    keys = Enum.map(values, key)

    if Enum.uniq(keys) == keys,
      do: :ok,
      else: Error.fail(:duplicate, [], "Duplicate declaration", %{values: keys})
  end

  def static(value) do
    case Jido.Codec.validate_static(value) do
      :ok ->
        :ok

      {:error, _reason} ->
        Error.fail(:live_value, [], "Authoring data cannot contain live values")
    end
  end

  def schema(schema) do
    case {Joi.Schema.kind(schema), Joi.Schema.fields(schema)} do
      {:map, {:ok, fields}} when is_list(fields) -> static_schema(schema)
      _ -> Error.fail(:invalid_schema, [], "Expected a static Joi object schema")
    end
  end

  defp static_schema(%{__struct__: _type} = value) do
    if Joi.Schema.coerce?(value) or
         Joi.Schema.forbidden_state_type?(value) or
         Enum.any?(Joi.Schema.effects(value), &Joi.Schema.transform_effect?/1) do
      Error.fail(:invalid_schema, [], "State schemas cannot convert values")
    else
      static_schema(Map.from_struct(value))
    end
  end

  defp static_schema(value) when is_map(value),
    do: schema_items(Enum.flat_map(value, fn {k, v} -> [k, v] end))

  defp static_schema(value) when is_list(value), do: schema_items(value)
  defp static_schema(value) when is_tuple(value), do: schema_items(Tuple.to_list(value))
  defp static_schema(value), do: static(value)

  defp schema_items(values) do
    with {:ok, _} <-
           list(values, fn value -> with :ok <- static_schema(value), do: {:ok, value} end),
         do: :ok
  end

  def initialize(schema, state) do
    with :ok <- plain_map(state),
         do: parse_value(Joi.Schema.put_unrecognized_keys(schema, :error), state)
  end

  def parse_value(schema, input) do
    case Joi.initialize(schema, input) do
      {:ok, initialized} ->
        {:ok, initialized}

      {:error, issues} ->
        if Enum.any?(issues, &Joi.Error.changed_value?/1) do
          Error.fail(
            :state_conversion,
            [],
            "State initialization can add defaults but cannot convert supplied values"
          )
        else
          Error.fail(:invalid_state, [], "State does not match its schema", %{issues: issues})
        end
    end
  end

  def complete(schema, state) do
    with :ok <- plain_map(state) do
      case Joi.validate(Joi.Schema.put_unrecognized_keys(schema, :error), state) do
        :ok ->
          :ok

        {:error, issues} ->
          cond do
            Enum.any?(issues, &Joi.Error.changed_value?/1) ->
              Error.fail(:state_conversion, [], "Validation cannot change stored state")

            Enum.any?(issues, &(Joi.Error.code(&1) == :required)) ->
              Error.fail(:incomplete_state, [], "State does not match its schema", %{
                issues: issues
              })

            true ->
              Error.fail(:invalid_state, [], "State does not match its schema", %{issues: issues})
          end
      end
    end
  end

  def path(value) when is_binary(value) do
    case Jido.Signal.Router.Route.validate_path(value, []) do
      :ok -> :ok
      {:error, _} -> Error.fail(:invalid_path, [], "Invalid Signal path", %{path: value})
    end
  end

  def path(_), do: Error.fail(:invalid_path, [], "Expected a Signal path string")

  def exact(value) do
    with :ok <- path(value) do
      if wildcard?(value),
        do: Error.fail(:wildcard_type, [], "Expected an exact Signal type"),
        else: :ok
    end
  end

  def wildcard?(value), do: String.contains?(value, "*")
  def matches?(type, path), do: Jido.Signal.Router.matches?(type, path)
end
