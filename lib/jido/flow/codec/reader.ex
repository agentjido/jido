defmodule Jido.Flow.Codec.Reader do
  @moduledoc false

  alias Jido.Flow.{Component, Error, FieldError}
  alias Jido.Codec.Registry
  alias Jido.Flow.Codec.{Limits, Paths, Value}

  @root [
    name: :name,
    description: :description,
    schema: :schema,
    output_schema: :schema,
    components: :components,
    output: {:value, :flow}
  ]
  @target_kinds %{"action" => :action, "flow" => :flow}
  @on_error %{"fail_fast" => :fail_fast, "collect_errors" => :collect_errors}

  @doc false
  @spec decode(term(), Jido.Codec.Registry.t()) ::
          {:ok, map(), Paths.t()} | {:error, [Exception.t()]}
  def decode(%{} = document, registry) when not is_struct(document) do
    with :ok <- Limits.check(document),
         :ok <- envelope(document) do
      record(Map.drop(document, ["type", "vsn"]), @root, registry, [], [])
    else
      {:error, errors} -> {:error, List.wrap(errors)}
    end
  end

  def decode(_document, _registry), do: failure("stored Flow document must be a map", [])

  defp envelope(%{"type" => "jido.flow", "vsn" => 2}), do: :ok

  defp envelope(%{"type" => "jido.flow", "vsn" => 1}),
    do:
      failure(
        "stored Flow document vsn 1 requires migration to vsn 2; Dispatch cannot be migrated automatically",
        ["vsn"]
      )

  defp envelope(%{"type" => "jido.flow"}),
    do: failure("stored Flow document vsn must be 2", ["vsn"])

  defp envelope(_document), do: failure("stored Flow document type must be jido.flow", ["type"])

  defp record(%{} = values, fields, registry, stored, canonical) when not is_struct(values) do
    known = Map.new(fields, fn {field, _} -> {Atom.to_string(field), field} end)
    unknown = Map.drop(values, Map.keys(known))

    with :ok <- reject_field_keys(unknown, [:kind | Keyword.keys(fields)], stored) do
      {values, paths} =
        Enum.reduce(fields, {unknown, %{canonical => stored}}, fn {field, type}, {result, paths} ->
          key = Atom.to_string(field)

          case Map.fetch(values, key) do
            :error ->
              {result, paths}

            {:ok, value} ->
              case field(type, value, registry, stored ++ [key], canonical ++ [field]) do
                {:ok, value, nested_paths} ->
                  {Map.put(result, field, value), Map.merge(paths, nested_paths)}

                {:error, nested} ->
                  {Map.put(result, field, FieldError.new(nested)), paths}
              end
          end
        end)

      {:ok, values, paths}
    end
  end

  defp record(_values, _fields, _registry, stored, canonical),
    do:
      {:ok,
       FieldError.new([
         Error.validation_error("stored Flow field must be a map", %{path: stored})
       ]), %{canonical => stored}}

  defp reject_field_keys(unknown, reserved, stored) do
    errors =
      unknown
      |> Map.keys()
      |> Enum.filter(&(&1 in reserved))
      |> Enum.sort()
      |> Enum.map(fn key ->
        Error.validation_error("unknown stored Flow field: #{inspect(key)}", %{
          key: key,
          path: stored ++ [Atom.to_string(key)]
        })
      end)

    if errors == [], do: :ok, else: {:error, errors}
  end

  defp field({type, _}, value, registry, stored, canonical)
       when type in [:value, :condition],
       do: Value.decode(value, registry, stored, canonical)

  defp field(:meta, value, registry, stored, canonical),
    do: Value.decode(value, registry, stored, canonical, :data)

  defp field(:schema, value, registry, stored, canonical),
    do: resolve(value, :schema, registry, stored, canonical)

  defp field({:call, _, _}, value, registry, stored, canonical),
    do: target(value, registry, stored, canonical, true)

  defp field({:target, _}, value, registry, stored, canonical),
    do: target(value, registry, stored, canonical, false)

  defp field(:state, value, registry, stored, canonical),
    do: record(value, Component.state_fields(), registry, stored, canonical)

  defp field(type, values, registry, stored, canonical) when type in [:wait_options, :options],
    do: sequence(values, &record(&1, option_fields(type), registry, &2, &3), stored, canonical)

  defp field(:parallel_actions, values, registry, stored, canonical),
    do:
      sequence(
        values,
        &record(&1, Component.parallel_action_fields(), registry, &2, &3),
        stored,
        canonical
      )

  defp field(:components, values, registry, stored, canonical),
    do: sequence(values, &component/4, stored, canonical, registry)

  defp field(:on_error, value, _registry, stored, canonical),
    do: closed(@on_error, value, "on_error", stored, canonical)

  defp field({:module, kind}, value, registry, stored, canonical),
    do: resolve(value, kind, registry, stored, canonical)

  defp field(:unresolved_target, _value, _registry, stored, canonical),
    do: {:ok, FieldError.new([]), %{canonical => stored}}

  defp field(_type, value, _registry, stored, canonical), do: {:ok, value, %{canonical => stored}}

  defp option_fields(:wait_options), do: Component.wait_option_fields()
  defp option_fields(:options), do: Component.option_fields()

  defp component(%{"kind" => kind} = value, registry, stored, canonical) do
    kind =
      Enum.find(
        [:call, :choice, :map, :parallel, :reduce, :iterate, :invoke, :handoff, :wait],
        &(Atom.to_string(&1) == kind)
      )

    if kind do
      with {:ok, value, paths} <-
             record(
               Map.delete(value, "kind"),
               Component.common_fields() ++ Component.fields(kind),
               registry,
               stored,
               canonical
             ) do
        {:ok, Map.put(value, :kind, kind), paths}
      end
    else
      failure("stored Flow component kind is not supported", stored ++ ["kind"])
    end
  end

  defp component(_value, _registry, stored, _canonical),
    do: failure("stored Flow component kind is required", stored ++ ["kind"])

  defp target(%{} = value, registry, stored, canonical, params?) when not is_struct(value) do
    {kind, kind_errors} =
      case Map.fetch(@target_kinds, Map.get(value, "kind")) do
        {:ok, kind} ->
          {kind, []}

        :error ->
          {nil,
           [
             Error.validation_error("stored Flow target kind must be action or flow", %{
               path: stored ++ ["kind"]
             })
           ]}
      end

    fields =
      [target: if(kind, do: {:module, kind}, else: :unresolved_target)] ++
        if(params?, do: [params: {:value, :flow}], else: [])

    with {:ok, value, paths} <-
           record(Map.delete(value, "kind"), fields, registry, stored, canonical) do
      {:ok, Map.put(value, :kind, if(kind, do: kind, else: FieldError.new(kind_errors))), paths}
    end
  end

  defp target(_value, _registry, stored, _canonical, _params),
    do: failure("stored Flow target must be a map", stored)

  defp resolve(value, kind, registry, stored, canonical) do
    with {:ok, resolved} <- Registry.decode_reference(registry, value, kind) do
      {:ok, resolved, %{canonical => stored}}
    else
      {:error, %Registry.Error{} = error} ->
        error = flow_registry_error(error)
        {:error, [Error.prefix_path(error, registry_error_path(value, error, stored))]}
    end
  end

  defp registry_error_path(%{}, %{details: %{field: field}}, stored)
       when is_binary(field),
       do: stored ++ [field]

  defp registry_error_path(_value, _error, stored), do: stored

  defp flow_registry_error(%Registry.Error{} = error) do
    message = String.replace(error.message, "Codec Registry", "flow registry")
    Error.validation_error(message, error.details)
  end

  defp closed(table, value, label, stored, canonical) do
    case Map.fetch(table, value) do
      {:ok, value} -> {:ok, value, %{canonical => stored}}
      :error -> failure("stored Flow #{label} is not supported", stored)
    end
  end

  defp sequence(values, decoder, stored, canonical, registry \\ nil)

  defp sequence(values, decoder, stored, canonical, registry) when is_list(values) do
    {values, paths} =
      values
      |> Enum.with_index()
      |> Enum.reduce({[], %{canonical => stored}}, fn {value, index}, {values, paths} ->
        result =
          if registry,
            do: decoder.(value, registry, stored ++ [index], canonical ++ [index]),
            else: decoder.(value, stored ++ [index], canonical ++ [index])

        case result do
          {:ok, value, nested_paths} -> {[value | values], Map.merge(paths, nested_paths)}
          {:error, nested} -> {[FieldError.new(nested) | values], paths}
        end
      end)

    {:ok, Enum.reverse(values), paths}
  end

  defp sequence(_values, _decoder, stored, _canonical, _registry),
    do: failure("stored Flow field must be a list", stored)

  defp failure(message, path), do: {:error, [Error.validation_error(message, %{path: path})]}
end
