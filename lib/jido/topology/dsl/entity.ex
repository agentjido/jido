defmodule Jido.Topology.DSL.Entity do
  @moduledoc false

  alias Jido.Topology.{DSL, EntryMetadata}

  @entries [
    {:agent, :agents, :agents, DSL.Agent},
    {:group, :groups, :agents, DSL.Group},
    {:resource, :resources, :resources, DSL.Bus},
    {:owns, :relationships, :relationships, DSL.Owns},
    {:subscribe, :connections, :connections, DSL.Subscribe},
    {:include, :includes, :topologies, DSL.Include},
    {:import, :imports, :imports, DSL.Import},
    {:export, :exports, :exports, DSL.Export}
  ]

  def entries, do: @entries

  def struct_fields(kind, overrides \\ []) do
    fields = Enum.map(EntryMetadata.schema(kind), fn {key, opts} -> {key, opts[:default]} end)
    [__spark_metadata__: nil] ++ Keyword.merge(fields, overrides)
  end

  # Optional values carry presence separately from the value. In particular,
  # an explicit nil must reach canonical validation even without debug metadata.
  def schema(fields) do
    Enum.map(fields, fn {key, opts} ->
      if optional?(opts),
        do: {key, Keyword.update!(opts, :type, &{:custom, __MODULE__, :present, [&1]})},
        else: {key, opts}
    end)
  end

  def present(value, type) do
    with {:ok, opts} <- Spark.Options.validate([value: value], value: [type: type]),
         do: {:ok, {:present, opts[:value]}}
  end

  def lower(%DSL.Import{} = entity), do: entity |> lower_fields(:import) |> Map.put(:kind, :bus)

  def lower(%DSL.Include{} = entity) do
    entity
    |> lower_fields(:include)
    |> Map.update!(:bindings, &Enum.map(&1, fn item -> lower_fields(item, :binding) end))
  end

  def lower(%module{} = entity) do
    {kind, _, _, _} = Enum.find(@entries, &(elem(&1, 3) == module))
    lower_fields(entity, kind)
  end

  defp lower_fields(entity, kind) do
    Enum.reduce(EntryMetadata.schema(kind), %{}, fn {field, opts}, attrs ->
      value = Map.fetch!(entity, field)
      optional? = optional?(opts) or (kind == :group and field == :count)

      case {optional?, value} do
        {true, nil} -> attrs
        {true, {:present, value}} -> Map.put(attrs, field, value)
        _ -> Map.put(attrs, field, value)
      end
    end)
  end

  defp optional?(opts),
    do: not Keyword.get(opts, :required, false) and not Keyword.has_key?(opts, :default)
end
