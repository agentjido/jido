defmodule Jido.Topology.DSL.Compiler do
  @moduledoc false
  use Spark.Dsl.Transformer

  alias Jido.Agent.Authoring
  alias Jido.Topology.EntryMetadata
  alias Jido.Topology.DSL.Entity, as: DslEntity
  alias Jido.Agent.Authoring.SourceMap
  alias Spark.Dsl.Extension

  # Spark stores entities before our final compiler runs. Check storage here,
  # after extension transformers, while the property annotations are available.
  @impl true
  def transform(dsl) do
    env = Spark.Dsl.Transformer.get_persisted(dsl, :env)

    error =
      for {kind, _field, section, module} <- DslEntity.entries(),
          entity <- section_entities(dsl, section),
          is_struct(entity, module),
          sources = SourceMap.entity(entity, []),
          field <- EntryMetadata.fields(kind),
          reduce: nil do
        nil ->
          line = SourceMap.lookup(sources, [field], env.line)

          case escape(Map.fetch!(entity, field), %{env | line: line}) do
            {:ok, _} -> nil
            {:error, error} -> error
          end

        error ->
          error
      end

    if error, do: {:error, error}, else: :ok
  end

  defmacro __before_compile__(env) do
    config = Module.get_attribute(env.module, :jido_agent_options)
    config = Map.drop(config, [:description])
    {extensions, config} = Map.pop(config, :extensions, [])
    validate_extensions!(extensions, env)
    extensions = Enum.filter(extensions, &extension?(&1, :lower_topology))
    dsl = Module.get_attribute(env.module, :spark_dsl_config) || %{}
    fields = opts(dsl, [:topology], [:schema, :metadata])

    entity_groups =
      for {_kind, field, section, module} <- DslEntity.entries() do
        entities = Enum.filter(section_entities(dsl, section), &is_struct(&1, module))
        {field, entities}
      end

    fields =
      Enum.reduce(entity_groups, fields, fn {field, entities}, fields ->
        put_entities(fields, field, entities)
      end)

    startup = section_opts(dsl, :startup)

    fields = if startup == %{}, do: fields, else: Map.put(fields, :startup, startup)
    overlap = Enum.filter(Map.keys(fields), &Map.has_key?(config, &1))

    if overlap != [],
      do: fail!(env, "Fields declared in both keyword and block form: #{inspect(overlap)}")

    defaults =
      Map.new(EntryMetadata.collections(), fn {_kind, field} -> {field, []} end)
      |> Map.merge(%{schema: Zoi.object(%{}), metadata: %{}, startup: %{}})

    config = Map.merge(defaults, Map.merge(config, fields))

    entities = foreign_entities(dsl)
    config = unwrap!(Jido.Topology.Extension.lower(extensions, config, entities), env)

    sources =
      Enum.reduce(entity_groups, field_sources(dsl), fn {field, entities}, locations ->
        entities
        |> Enum.with_index()
        |> Enum.reduce(locations, fn {entity, index}, acc ->
          Map.merge(acc, source_locations(entity, [field, index]))
        end)
      end)

    owner? = Module.get_attribute(env.module, :jido_agent_block_declared) == true
    escaped_config = Jido.Topology.unwrap!(escape(config, env))

    quote do
      @doc false
      def __topology_owner__?, do: unquote(owner?)
      @doc false
      def __topology_config__, do: unquote(escaped_config)

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
      {:error, error} -> fail_from_source(module.__topology_sources__(), error, env)
    end
  end

  @spec fail_from_source(map(), Exception.t(), map()) :: no_return()
  defp fail_from_source(sources, error, env) do
    path = Map.get(error.details || %{}, :source_path, [])
    line = SourceMap.lookup(sources, path, env.line)
    fail!(%{env | line: line}, Exception.message(error))
  end

  defp field_sources(dsl) do
    SourceMap.section(dsl, [:topology], [:schema, :metadata], [])
    |> Map.merge(
      SourceMap.section(dsl, [:topology, :startup], EntryMetadata.fields(:startup), [:startup])
    )
  end

  defp source_locations(entity, path) do
    entity
    |> Map.get(:bindings, [])
    |> Enum.with_index()
    |> Enum.reduce(SourceMap.entity(entity, path), fn {binding, index}, acc ->
      Map.merge(acc, source_locations(binding, path ++ [:bindings, index]))
    end)
  end

  defp opts(dsl, path, keys) do
    Enum.reduce(keys, %{}, fn key, acc ->
      case Extension.fetch_opt(dsl, path, key) do
        {:ok, value} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
  end

  defp section_entities(dsl, section), do: Extension.get_entities(dsl, [:topology, section])

  defp section_opts(dsl, :startup) do
    keys = EntryMetadata.fields(:startup)
    opts(dsl, [:topology, :startup], keys)
  end

  defp put_entities(fields, _, []), do: fields

  defp put_entities(fields, key, entities) do
    values = Enum.map(entities, &DslEntity.lower/1)

    Map.put(fields, key, values)
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

  defp core_entity?([:topology, section], entity) do
    Enum.any?(DslEntity.entries(), fn {_kind, _field, candidate, module} ->
      section == candidate and is_struct(entity, module)
    end)
  end

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

  defp escape(value, env) do
    {:ok, Macro.escape(value)}
  rescue
    ArgumentError ->
      {:error,
       CompileError.exception(
         file: env.file,
         line: env.line,
         description: "Topology data must not contain runtime values"
       )}
  end

  defp unwrap!({:error, %{details: %{entities: [entity | _]}} = error}, env),
    do: fail!(Authoring.location(env, entity), Exception.message(error))

  defp unwrap!({:ok, value}, _), do: value
  defp unwrap!({:error, error}, env), do: fail!(env, Exception.message(error))

  defp fail!(env, message),
    do: raise(CompileError, file: env.file, line: env.line, description: message)
end
