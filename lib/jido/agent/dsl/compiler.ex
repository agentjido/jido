defmodule Jido.Agent.DSL.Compiler do
  @moduledoc false

  alias Jido.Agent.Authoring
  alias Jido.Agent.Authoring.SourceMap
  alias Spark.Dsl.Extension

  defmacro __before_compile__(env) do
    options = Module.get_attribute(env.module, :jido_agent_options)
    host = Module.get_attribute(env.module, :jido_agent_host)
    {extensions, options} = Map.pop(options, :extensions, [])
    {agent_extensions, topology_extensions} = extensions(host, extensions, env)
    config = host_config(host, options, env)
    # Read current compile state once. Loaded module code can be stale on reload.
    dsl = Module.get_attribute(env.module, :spark_dsl_config) || %{}
    agent = lower(config, agent_extensions, dsl, env)

    topology =
      if host == :topology,
        do: Jido.Topology.DSL.Compiler.lower(options, topology_extensions, dsl, env)

    quote do
      unquote(agent)
      unquote(topology)
      @after_verify {Jido.Agent.DSL.Compiler, :verify}
    end
  end

  defp lower(config, extensions, dsl, env) do
    routes = Extension.get_entities(dsl, [:routes])
    source = Extension.get_opt(dsl, [:routes], :signal_source)

    if (routes != [] or source != nil) and
         is_nil(Module.get_attribute(env.module, :jido_agent_block_declared)) do
      fail!(env, "An agent block is required when routes are declared")
    end

    {plugins, entities} =
      dsl
      |> Extension.get_entities([:agent])
      |> Enum.split_with(&match?(%Jido.Agent.DSL.Plugin{}, &1))

    sources = sources(dsl, routes, plugins)

    config =
      config
      |> Map.put_new(:description, nil)
      |> Map.merge(block_fields(dsl, routes, plugins, env, sources))

    config = unwrap!(Jido.Agent.Extension.lower(extensions, config, entities), env)

    definition =
      unwrap!(Jido.Agent.Validation.module_definition(env.module, config), env, sources)

    if extensions != [],
      do: validate_lowered_routes!(routes, definition.routes, env)

    generated = generate(routes, source, env)

    quote do
      @doc false
      def __agent_config__, do: unquote(Macro.escape(definition))
      @doc false
      def __agent_sources__, do: unquote(Macro.escape(sources))

      unquote_splicing(generated)
    end
  end

  @doc false
  def register_agent_block!(module),
    do: Module.put_attribute(module, :jido_agent_block_declared, true)

  defp host_config(:topology, config, _env),
    do: Map.take(config, [:name, :description, :vsn])

  defp host_config(:agent, config, env) do
    unwrap!(Authoring.keys(config, [:name, :description, :vsn]), env)
    config
  end

  defp extensions(:agent, extensions, _env), do: {extensions, []}

  defp extensions(:topology, extensions, env) do
    unwrap!(
      Authoring.traverse(extensions, fn extension ->
        if extension?(extension, :lower_agent) or extension?(extension, :lower_topology),
          do: {:ok, extension},
          else:
            Authoring.error(
              "Authoring extension must implement lower_agent/2 or lower_topology/2"
            )
      end),
      env
    )

    {Enum.filter(extensions, &extension?(&1, :lower_agent)),
     Enum.filter(extensions, &extension?(&1, :lower_topology))}
  end

  defp validate_lowered_routes!(routes, lowered, env) do
    for route <- routes, not is_nil(route.as) do
      case Enum.filter(lowered, &(&1.path == route.path)) do
        [final] when is_nil(final.match) ->
          :ok

        _ ->
          fail!(
            Authoring.location(env, route),
            "An exposed Signal type must retain exactly one route without a match predicate after lowering"
          )
      end
    end
  end

  def verify(module) do
    env = %{file: to_string(module.module_info(:compile)[:source]), line: 1}
    unwrap!(Jido.Agent.Source.definition(module), env, module.__agent_sources__())

    if function_exported?(module, :__topology_config__, 0),
      do: Jido.Topology.DSL.Compiler.verify(module)

    :ok
  end

  defp sources(dsl, routes, plugins) do
    locations = SourceMap.section(dsl, [:agent], [:schema, :metadata], [])
    locations = Map.merge(locations, SourceMap.section(dsl, [:agent], [], [:plugins]))

    Enum.reduce([routes: routes, plugins: plugins], locations, fn {field, entities}, sources ->
      entities
      |> Enum.with_index()
      |> Enum.reduce(sources, fn {entity, index}, sources ->
        Map.merge(sources, SourceMap.entity(entity, [field, index]))
      end)
    end)
  end

  defp block_fields(dsl, routes, plugins, env, sources) do
    %{
      schema: Extension.get_opt(dsl, [:agent], :schema, Zoi.object(%{})),
      metadata: Extension.get_opt(dsl, [:agent], :metadata, %{}),
      routes: Enum.map(routes, &lower_route(&1, env)),
      plugins:
        Enum.map(Enum.with_index(plugins), fn {plugin, index} ->
          options = Authoring.options(plugin.config) |> Authoring.at([:plugins, index])
          {plugin.module, unwrap!(options, env, sources)}
        end)
    }
  end

  defp lower_route(route, env) do
    opts = [priority: route.priority, match: route.match]
    opts = if is_nil(route.defaults), do: opts, else: Keyword.put(opts, :defaults, route.defaults)
    unwrap!(Authoring.route(route.path, route.target, opts), Authoring.location(env, route))
  end

  defp generate(routes, source, env) do
    route_counts = Enum.frequencies_by(routes, & &1.path)
    exposed = Enum.reject(routes, &is_nil(&1.as))
    names = Enum.frequencies_by(exposed, & &1.as)

    source_result =
      if exposed != [] do
        if is_binary(source),
          do: Jido.Signal.validate_uri_reference(source, []),
          else: :missing
      else
        :ok
      end

    Enum.map(exposed, fn route ->
      env = Authoring.location(env, route)

      if String.contains?(route.path, "*") or route.match != nil,
        do: fail!(env, "as: requires an exact route without a match predicate")

      if Map.fetch!(route_counts, route.path) > 1,
        do: fail!(env, "An exposed Signal type must have exactly one route")

      case source_result do
        :ok -> :ok
        :missing -> fail!(env, "signal_source is required for as:")
        {:error, reason} -> fail!(env, "Invalid signal_source: #{reason}")
      end

      if Map.fetch!(names, route.as) > 1, do: fail!(env, "Duplicate interface name")
      name = String.to_atom("#{route.as}_signal")

      for arity <- [1, 2] do
        if Module.defines?(env.module, {name, arity}),
          do: fail!(env, "Generated function conflicts with #{name}/#{arity}")
      end

      Jido.Agent.DSL.Generator.function(name, route.path, source)
    end)
  end

  defp extension?(module, callback) when is_atom(module) and not is_nil(module),
    do: Code.ensure_loaded?(module) and function_exported?(module, callback, 2)

  defp extension?(_module, _callback), do: false

  defp unwrap!(:ok, _env), do: :ok
  defp unwrap!({:ok, value}, _env), do: value
  defp unwrap!({:error, error}, env), do: fail!(env, Exception.message(error))

  defp unwrap!({:ok, value}, _env, _sources), do: value

  defp unwrap!({:error, error}, env, sources) do
    line = SourceMap.lookup(sources, Map.get(error.details || %{}, :source_path, []), env.line)
    fail!(%{env | line: line}, Exception.message(error))
  end

  defp fail!(env, message),
    do: raise(CompileError, file: env.file, line: env.line, description: message)
end
