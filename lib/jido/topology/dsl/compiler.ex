defmodule Jido.Topology.DSL.Compiler do
  @moduledoc false
  alias Jido.Agent.Authoring
  alias Jido.Topology.DSL
  alias Jido.Topology.Validation
  alias Spark.Dsl.Entity
  alias Spark.Dsl.Extension

  defmacro __before_compile__(env) do
    original = Module.get_attribute(env.module, :topology_options)
    config = unwrap!(Authoring.attrs(original), env)
    config = Map.drop(config, [:description, :max_state_size])
    {extensions, config} = Map.pop(config, :extensions, [])
    validate_extensions!(extensions, env)
    extensions = Enum.filter(extensions, &extension?(&1, :lower_topology))
    dsl = Module.get_attribute(env.module, :spark_dsl_config) || %{}
    agents = section_entities(dsl, :agents, env)
    fields = opts(dsl, [:topology], [:schema, :metadata])

    entity_groups = [
      {:agents, :agent, Enum.filter(agents, &is_struct(&1, DSL.Agent))},
      {:groups, :group, Enum.filter(agents, &is_struct(&1, DSL.Group))},
      {:resources, :bus, core_entities(:resources, section_entities(dsl, :resources, env))},
      {:relationships, :owns,
       core_entities(:relationships, section_entities(dsl, :relationships, env))},
      {:connections, :subscribe,
       core_entities(:connections, section_entities(dsl, :connections, env))},
      {:includes, :include, core_entities(:topologies, section_entities(dsl, :topologies, env))},
      {:imports, :import, core_entities(:imports, section_entities(dsl, :imports, env))},
      {:exports, :export, core_entities(:exports, section_entities(dsl, :exports, env))}
    ]

    fields =
      Enum.reduce(entity_groups, fields, fn {field, _kind, entities}, fields ->
        put_entities(fields, field, entities)
      end)

    startup = section_opts(dsl, :startup, env)

    fields = if startup == %{}, do: fields, else: Map.put(fields, :startup, startup)
    overlap = Enum.filter(Map.keys(fields), &Map.has_key?(config, &1))

    if overlap != [],
      do: fail!(env, "Fields declared in both keyword and block form: #{inspect(overlap)}")

    config =
      Map.merge(
        %{
          schema: Zoi.object(%{}),
          metadata: %{},
          agents: [],
          groups: [],
          resources: [],
          relationships: [],
          connections: [],
          includes: [],
          imports: [],
          exports: [],
          startup: %{}
        },
        Map.merge(config, fields)
      )

    entities = foreign_entities(dsl)
    config = unwrap!(Jido.Topology.Extension.lower(extensions, config, entities), env)

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

  @doc false
  def register_startup_location!(module, location, env) do
    case Module.get_attribute(module, :jido_topology_startup_location) do
      nil -> Module.put_attribute(module, :jido_topology_startup_location, location)
      ^location -> :ok
      _other -> fail!(env, "Topology section :startup cannot be declared in both locations")
    end
  end

  defp fail_from_source(config, sources, error, env) do
    located =
      Enum.find_value(sources, fn source ->
        with entries when is_list(entries) <- Map.get(config, source.field),
             {:ok, entry} <- Enum.fetch(entries, source.index),
             {:error, source_error} <- Validation.entry(source.kind, entry) do
          {source, source_error}
        else
          _other -> nil
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

  defp opts(dsl, path, keys) do
    Enum.reduce(keys, %{}, fn key, acc ->
      case Extension.fetch_opt(dsl, path, key) do
        {:ok, value} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
  end

  defp section_entities(dsl, section, env) do
    legacy = Extension.get_entities(dsl, [section])
    nested = Extension.get_entities(dsl, [:topology, section])

    if legacy != [] and nested != [] do
      fail!(env, "Topology section #{inspect(section)} cannot be declared in both locations")
    end

    legacy ++ nested
  end

  defp section_opts(dsl, :startup, env) do
    keys = [:concurrency, :ready, :max_agents, :retry_interval, :task_timeout]
    legacy = opts(dsl, [:startup], keys)
    nested = opts(dsl, [:topology, :startup], keys)

    if legacy != %{} and nested != %{} do
      fail!(env, "Topology section :startup cannot be declared in both locations")
    end

    Map.merge(legacy, nested)
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

  defp foreign_entities(dsl) do
    dsl
    |> Enum.filter(fn {path, value} -> is_list(path) and is_map(value) end)
    |> Enum.reject(fn {path, _value} -> List.first(path) in [:agent, :routes] end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.flat_map(fn {path, _value} ->
      dsl
      |> Extension.get_entities(path)
      |> Enum.reject(&core_entity?(path, &1))
    end)
  end

  defp core_entities(section, entities),
    do: Enum.filter(entities, &core_entity?([section], &1))

  defp core_entity?([:topology, section], entity), do: core_entity?([section], entity)

  defp core_entity?([:agents], entity),
    do: is_struct(entity, DSL.Agent) or is_struct(entity, DSL.Group)

  defp core_entity?([:resources], entity), do: is_struct(entity, DSL.Bus)
  defp core_entity?([:relationships], entity), do: is_struct(entity, DSL.Owns)
  defp core_entity?([:connections], entity), do: is_struct(entity, DSL.Subscribe)
  defp core_entity?([:topologies], entity), do: is_struct(entity, DSL.Include)
  defp core_entity?([:imports], entity), do: is_struct(entity, DSL.Import)
  defp core_entity?([:exports], entity), do: is_struct(entity, DSL.Export)

  defp core_entity?(_path, _entity), do: false

  defp validate_extensions!(extensions, env) when is_list(extensions) do
    invalid =
      Enum.find(extensions, fn extension ->
        not extension?(extension, :lower_agent) and
          not extension?(extension, :lower_topology)
      end)

    if invalid do
      fail!(env, "Authoring extension must implement lower_agent/2 or lower_topology/2")
    end
  end

  defp validate_extensions!(_extensions, env),
    do: fail!(env, "Topology extensions must be a list")

  defp extension?(module, callback) when is_atom(module) and not is_nil(module),
    do: Code.ensure_loaded?(module) and function_exported?(module, callback, 2)

  defp extension?(_module, _callback), do: false

  defp unwrap!({:error, %{details: %{entities: [entity | _]}} = error}, env),
    do: fail!(location(env, entity), Exception.message(error))

  defp unwrap!({:ok, value}, _), do: value
  defp unwrap!({:error, error}, env), do: fail!(env, Exception.message(error))

  defp location(env, %{__spark_metadata__: %{anno: anno}}) when not is_nil(anno),
    do: %{env | line: :erl_anno.line(anno)}

  defp location(env, _entity), do: env

  defp fail!(env, message),
    do: raise(CompileError, file: env.file, line: env.line, description: message)
end
