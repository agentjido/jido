defmodule Jido.Topology.DSL.Compiler do
  @moduledoc false
  alias Jido.Agent.Authoring
  alias Jido.Topology.DSL
  alias Jido.Topology.Validation
  alias Spark.Dsl.Entity
  alias Spark.Dsl.Extension

  defmacro __before_compile__(env) do
    config = unwrap!(Authoring.attrs(Module.get_attribute(env.module, :topology_options)), env)
    dsl = Module.get_attribute(env.module, :spark_dsl_config) || %{}
    agents = Extension.get_entities(dsl, [:agents])
    fields = opts(dsl, :topology, [:schema, :metadata])

    entity_groups = [
      {:agents, :agent, Enum.filter(agents, &is_struct(&1, DSL.Agent))},
      {:groups, :group, Enum.filter(agents, &is_struct(&1, DSL.Group))},
      {:resources, :bus, Extension.get_entities(dsl, [:resources])},
      {:relationships, :owns, Extension.get_entities(dsl, [:relationships])},
      {:connections, :subscribe, Extension.get_entities(dsl, [:connections])},
      {:includes, :include, Extension.get_entities(dsl, [:topologies])},
      {:imports, :import, Extension.get_entities(dsl, [:imports])},
      {:exports, :export, Extension.get_entities(dsl, [:exports])}
    ]

    fields =
      Enum.reduce(entity_groups, fields, fn {field, _kind, entities}, fields ->
        put_entities(fields, field, entities)
      end)

    startup =
      opts(dsl, :startup, [:concurrency, :ready, :max_agents, :retry_interval, :task_timeout])

    fields = if startup == %{}, do: fields, else: Map.put(fields, :startup, startup)
    overlap = Enum.filter(Map.keys(fields), &Map.has_key?(config, &1))

    if overlap != [],
      do: fail!(env, "Fields declared in both keyword and block form: #{inspect(overlap)}")

    config = Map.merge(config, fields)

    sources =
      Enum.flat_map(entity_groups, fn {field, kind, entities} ->
        sources(entities, field, kind)
      end)

    quote do
      @doc false
      def __topology_config__, do: unquote(Macro.escape(config))

      @doc false
      def __topology_sources__, do: unquote(Macro.escape(sources))

      @after_verify {Jido.Topology.DSL.Compiler, :verify}
    end
  end

  def verify(module) do
    env = %{file: to_string(module.module_info(:compile)[:source]), line: 1}
    config = module.__topology_config__()

    case Jido.Topology.new(config) do
      {:ok, _definition} -> :ok
      {:error, error} -> fail_from_source(config, module.__topology_sources__(), error, env)
    end
  end

  defp fail_from_source(config, sources, error, env) do
    located =
      Enum.find_value(sources, fn source ->
        entry = config |> Map.fetch!(source.field) |> Enum.fetch!(source.index)

        case Validation.entry(source.kind, entry) do
          {:ok, _entry} -> nil
          {:error, source_error} -> {source, source_error}
        end
      end)

    case located do
      {source, source_error} -> fail!(%{env | line: source.line}, Exception.message(source_error))
      nil -> fail!(env, Exception.message(error))
    end
  end

  defp sources(entities, field, kind) do
    entities
    |> Enum.with_index()
    |> Enum.map(fn {entity, index} -> source(field, kind, index, entity) end)
  end

  defp source(field, kind, index, entity) do
    %{field: field, kind: kind, index: index, line: source_line(entity)}
  end

  defp source_line(%_{} = entity) do
    property_annos =
      entity
      |> Map.from_struct()
      |> Map.keys()
      |> Enum.map(&Entity.property_anno(entity, &1))

    [Entity.anno(entity) | property_annos]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&:erl_anno.line/1)
    |> Enum.reject(&(&1 == 1))
    |> Enum.min(fn -> annotation_line(Entity.anno(entity)) end)
  end

  defp source_line(_entity), do: 1

  defp annotation_line(nil), do: 1
  defp annotation_line(annotation), do: :erl_anno.line(annotation)

  defp opts(dsl, section, keys) do
    Enum.reduce(keys, %{}, fn key, acc ->
      case Extension.fetch_opt(dsl, [section], key) do
        {:ok, value} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
  end

  defp put_entities(fields, _, []), do: fields

  defp put_entities(fields, key, entities) do
    values = Enum.map(entities, &lower/1)

    Map.put(fields, key, values)
  end

  defp lower(entity) do
    value =
      entity
      |> Map.from_struct()
      |> Map.delete(:__spark_metadata__)
      |> Map.reject(fn {_, value} -> is_nil(value) end)

    if Map.has_key?(value, :bindings),
      do: Map.update!(value, :bindings, &Enum.map(&1, fn binding -> lower(binding) end)),
      else: value
  end

  defp unwrap!({:ok, value}, _), do: value
  defp unwrap!({:error, error}, env), do: fail!(env, Exception.message(error))

  defp fail!(env, message),
    do: raise(CompileError, file: env.file, line: env.line, description: message)
end
