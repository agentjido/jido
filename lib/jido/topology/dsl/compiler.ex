defmodule Jido.Topology.DSL.Compiler do
  @moduledoc false
  alias Jido.Agent.Authoring
  alias Jido.Topology.DSL
  alias Spark.Dsl.Extension

  defmacro __before_compile__(env) do
    config = unwrap!(Authoring.attrs(Module.get_attribute(env.module, :topology_options)), env)
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
          put_entities(fields, section, Extension.get_entities(dsl, [section]))
        end
      )

    fields = put_entities(fields, :includes, Extension.get_entities(dsl, [:topologies]))

    startup =
      opts(dsl, :startup, [:concurrency, :ready, :max_agents, :retry_interval, :task_timeout])

    fields = if startup == %{}, do: fields, else: Map.put(fields, :startup, startup)
    overlap = Enum.filter(Map.keys(fields), &Map.has_key?(config, &1))

    if overlap != [],
      do: fail!(env, "Fields declared in both keyword and block form: #{inspect(overlap)}")

    config = Map.merge(config, fields)

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

  defp unwrap!({:ok, value}, _), do: value
  defp unwrap!({:error, error}, env), do: fail!(env, Exception.message(error))

  defp fail!(env, message),
    do: raise(CompileError, file: env.file, line: env.line, description: message)
end
