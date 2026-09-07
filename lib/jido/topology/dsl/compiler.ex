defmodule Jido.Topology.DSL.Compiler do
  @moduledoc false
  alias Jido.Agent.Authoring
  alias Jido.Topology.DSL
  alias Spark.Dsl.Extension

  defmacro __before_compile__(env) do
    original = Module.get_attribute(env.module, :topology_options)
    config = unwrap!(Authoring.attrs(original), env)
    {extensions, config} = Map.pop(config, :extensions, [])
    dsl = Module.get_attribute(env.module, :spark_dsl_config) || %{}
    agents = Extension.get_entities(dsl, [:agents])
    fields = opts(dsl, :topology, [:schema, :metadata])
    fields = put_entities(fields, :agents, Enum.filter(agents, &is_struct(&1, DSL.Agent)))
    fields = put_entities(fields, :groups, Enum.filter(agents, &is_struct(&1, DSL.Group)))

    fields =
      Enum.reduce(
        [:resources, :relationships, :connections, :imports, :exports],
        fields,
        fn section, fields ->
          entities = Extension.get_entities(dsl, [section])
          put_entities(fields, section, core_entities(section, entities))
        end
      )

    includes = core_entities(:topologies, Extension.get_entities(dsl, [:topologies]))
    fields = put_entities(fields, :includes, includes)

    startup =
      opts(dsl, :startup, [:concurrency, :ready, :max_agents, :retry_interval, :task_timeout])

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

    quote do
      @doc false
      def __topology_config__, do: unquote(Macro.escape(config))
      @after_verify {Jido.Topology.DSL.Compiler, :verify}
    end
  end

  def verify(module) do
    env = %{file: to_string(module.module_info(:compile)[:source]), line: 1}
    unwrap!(Jido.Topology.new(module.__topology_config__()), env)
    :ok
  end

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

  defp foreign_entities(dsl) do
    dsl
    |> Enum.filter(fn {path, value} -> is_list(path) and is_map(value) end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.flat_map(fn {path, _value} ->
      dsl
      |> Extension.get_entities(path)
      |> Enum.reject(&core_entity?(path, &1))
    end)
  end

  defp core_entities(section, entities),
    do: Enum.filter(entities, &core_entity?([section], &1))

  defp core_entity?([:agents], entity),
    do: is_struct(entity, DSL.Agent) or is_struct(entity, DSL.Group)

  defp core_entity?([:resources], entity), do: is_struct(entity, DSL.Bus)
  defp core_entity?([:relationships], entity), do: is_struct(entity, DSL.Owns)
  defp core_entity?([:connections], entity), do: is_struct(entity, DSL.Subscribe)
  defp core_entity?([:topologies], entity), do: is_struct(entity, DSL.Include)
  defp core_entity?([:imports], entity), do: is_struct(entity, DSL.Import)
  defp core_entity?([:exports], entity), do: is_struct(entity, DSL.Export)
  defp core_entity?(_path, _entity), do: false

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
