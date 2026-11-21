defmodule Jido.Agent.Schema do
  @moduledoc false

  alias Jido.Error
  alias Jido.Joi

  @agent_module Module.concat(["Jido", "Agent"])
  @agent_schema Joi.struct(@agent_module, %{
                  id: Joi.string() |> Joi.nullable() |> Joi.default(nil),
                  state: Joi.map() |> Joi.nullable() |> Joi.default(nil),
                  module: Joi.atom() |> Joi.nullable() |> Joi.default(nil),
                  name: Joi.string() |> Joi.min(1),
                  description: Joi.string() |> Joi.nullable() |> Joi.default(nil),
                  vsn: Joi.integer() |> Joi.min(1) |> Joi.default(1),
                  schema: Joi.any() |> Joi.default(Joi.object(%{})),
                  initial_state: Joi.map() |> Joi.default(%{}),
                  metadata: Joi.map() |> Joi.default(%{}),
                  signal_source: Joi.string() |> Joi.min(1) |> Joi.nullable() |> Joi.default(nil),
                  routes: Joi.list(Joi.any()) |> Joi.default([]),
                  topology: Joi.map() |> Joi.default(%{}),
                  plugins: Joi.list(Joi.any()) |> Joi.default([])
                })
  @defaults Map.new(Joi.struct_fields(@agent_schema), fn
              {key, value} -> {key, value}
              key -> {key, nil}
            end)

  @doc false
  def agent_module, do: @agent_module

  @doc false
  def agent?(%{__struct__: @agent_module}), do: true
  def agent?(_value), do: false

  @doc false
  def agent_schema, do: @agent_schema

  @doc false
  def defaults, do: @defaults

  def attrs(value) do
    case to_attrs(value, :reject) do
      {:ok, attrs} -> {:ok, attrs}
      :error when is_list(value) -> authoring_error("Expected unique keyword options", %{value: value})
      :error -> authoring_error("Expected a map or keyword list", %{value: value})
    end
  end

  # Public boundaries keep their own duplicate policy and error context.
  def to_attrs(value, duplicates \\ :last)
  def to_attrs(value, _duplicates) when is_map(value) and not is_struct(value), do: {:ok, value}

  def to_attrs(value, duplicates) when is_list(value) do
    if Keyword.keyword?(value) and
         (duplicates == :last or Enum.uniq(Keyword.keys(value)) == Keyword.keys(value)),
       do: {:ok, Map.new(value)},
       else: :error
  end

  def to_attrs(_value, _duplicates), do: :error

  def keys(map, allowed) do
    case Map.keys(map) -- allowed do
      [] -> :ok
      unknown -> authoring_error("Unknown authoring fields", %{keys: unknown})
    end
  end

  def traverse(values, fun), do: traverse(values, fun, [])
  defp traverse([], _fun, acc), do: {:ok, Enum.reverse(acc)}

  defp traverse([value | tail], fun, acc) do
    case fun.(value) do
      {:ok, result} -> traverse(tail, fun, [result | acc])
      {:error, _error} = error -> error
    end
  end

  defp traverse(_tail, _fun, _acc), do: authoring_error("Expected a proper list")

  def authoring_error(message, details \\ %{}),
    do: {:error, Error.validation_error(message, kind: :config, details: details)}

  def fields(value, allowed, defaults \\ %{}) do
    with :ok <- plain_map(value),
         [] <- Map.keys(value) -- allowed do
      {:ok, Map.merge(defaults, value)}
    else
      keys when is_list(keys) -> Error.validation_result(:unknown_fields, [], "Unknown fields", %{keys: keys})
      error -> error
    end
  end

  def plain_map(value) when is_map(value) and not is_struct(value), do: :ok
  def plain_map(_), do: Error.validation_result(:invalid_map, [], "Expected a plain Map")

  def nonempty(value) when is_binary(value) and byte_size(value) > 0, do: :ok
  def nonempty(_), do: Error.validation_result(:invalid_string, [], "Expected a nonempty string")

  def name(value) when is_atom(value) and value not in [nil, true, false], do: :ok
  def name(_), do: Error.validation_result(:invalid_name, [], "Expected a name atom")

  def positive(value) when is_integer(value) and value > 0, do: :ok
  def positive(_), do: Error.validation_result(:invalid_positive, [], "Expected a positive integer")

  def list(values, fun), do: walk(values, fun, 0, [])
  defp walk([], _fun, _index, acc), do: {:ok, Enum.reverse(acc)}

  defp walk([value | tail], fun, index, acc) do
    with {:ok, value} <- Error.prefix_result_path(fun.(value), [index]),
         do: walk(tail, fun, index + 1, [value | acc])
  end

  defp walk(_, _, _, _), do: Error.validation_result(:invalid_list, [], "Expected a proper list")

  def unique(values, key) do
    keys = Enum.map(values, key)

    if Enum.uniq(keys) == keys,
      do: :ok,
      else: Error.validation_result(:duplicate, [], "Duplicate declaration", %{values: keys})
  end

  def static(value) do
    case Joi.validate_static(value) do
      :ok ->
        :ok

      {:error, _reason} ->
        Error.validation_result(:live_value, [], "Authoring data cannot contain live values")
    end
  end

  def schema(schema) do
    case {Joi.Schema.kind(schema), Joi.Schema.fields(schema)} do
      {:map, {:ok, fields}} when is_list(fields) ->
        case Joi.Schema.validate_stored(schema) do
          :ok -> static(schema)
          {:error, _reason} -> Error.validation_result(:invalid_schema, [], "Invalid stored-state schema")
        end

      _ ->
        Error.validation_result(:invalid_schema, [], "Expected a static Joi object schema")
    end
  end

  def initialize(schema, state) do
    with :ok <- plain_map(state),
         do: parse_value(Joi.Schema.close(schema), state)
  end

  def parse_value(schema, input) do
    case Joi.initialize(schema, input) do
      {:ok, initialized} ->
        {:ok, initialized}

      {:error, issues} ->
        if Enum.any?(issues, &(Joi.changed_value?(&1) or invalid_stored_schema?(&1))) do
          Error.validation_result(
            :state_conversion,
            [],
            "State initialization can add defaults but cannot convert supplied values"
          )
        else
          Error.validation_result(:invalid_state, [], "State does not match its schema", %{issues: issues})
        end
    end
  end

  def complete(schema, state) do
    with :ok <- plain_map(state) do
      case Joi.validate(Joi.Schema.close(schema), state) do
        :ok ->
          :ok

        {:error, issues} ->
          cond do
            Enum.any?(issues, &(Joi.changed_value?(&1) or invalid_stored_schema?(&1))) ->
              Error.validation_result(:state_conversion, [], "Validation cannot change stored state")

            Enum.any?(issues, &(Joi.error_code(&1) == :required)) ->
              Error.validation_result(:incomplete_state, [], "State does not match its schema", %{
                issues: issues
              })

            true ->
              Error.validation_result(:invalid_state, [], "State does not match its schema", %{issues: issues})
          end
      end
    end
  end

  defp invalid_stored_schema?(issue),
    do: Joi.error_code(issue) == :joi_invalid_stored_schema

  def path(value) when is_binary(value) do
    case Jido.Signal.Router.Route.validate_path(value, []) do
      :ok -> :ok
      {:error, _} -> Error.validation_result(:invalid_path, [], "Invalid Signal path", %{path: value})
    end
  end

  def path(_), do: Error.validation_result(:invalid_path, [], "Expected a Signal path string")

  def exact(value) do
    with :ok <- path(value) do
      if wildcard?(value),
        do: Error.validation_result(:wildcard_type, [], "Expected an exact Signal type"),
        else: :ok
    end
  end

  def wildcard?(value), do: String.contains?(value, "*")
  def matches?(type, path), do: Jido.Signal.Router.matches?(type, path)

  def options(opts, allowed) when is_list(opts) do
    if Keyword.keyword?(opts) and
         length(Keyword.keys(opts)) == length(Enum.uniq(Keyword.keys(opts))),
       do: fields(Map.new(opts), allowed),
       else: Error.validation_result(:invalid_options, [], "Expected unique keyword options")
  end

  def options(opts, allowed), do: fields(opts, allowed)
end
