defmodule Jido.Agent.DSL.Compiler do
  @moduledoc false

  alias Jido.Agent.Authoring
  alias Spark.Dsl.Extension

  defmacro __before_compile__(env) do
    original = Module.get_attribute(env.module, :jido_agent_options)
    config = unwrap!(Authoring.attrs(original), env)
    config = host_config(config, env)
    {extensions, config} = Map.pop(config, :extensions, [])

    extensions =
      if Module.get_attribute(env.module, :jido_agent_combined_extensions) do
        Enum.filter(extensions, &extension?(&1, :lower_agent))
      else
        extensions
      end

    # Module access can read an older loaded version during recompilation.
    dsl = Module.get_attribute(env.module, :spark_dsl_config) || %{}
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

    config =
      config
      |> Map.put_new(:description, nil)
      |> Map.merge(block_fields(dsl, routes, plugins, env))

    config = unwrap!(Jido.Agent.Extension.lower(extensions, config, entities), env)
    config = Map.put_new(config, :vsn, 1)

    unless is_integer(config.vsn) and config.vsn > 0 do
      fail!(env, "Agent vsn must be a positive integer")
    end

    if extensions != [],
      do: validate_lowered_routes!(routes, Map.get(config, :routes, []), env)

    generated = generate(routes, source, env)

    quote do
      @doc false
      def __agent_config__, do: unquote(Macro.escape(config))

      unquote_splicing(generated)

      @after_verify {Jido.Agent.DSL.Compiler, :verify}
    end
  end

  @doc false
  def register_agent_block!(module),
    do: Module.put_attribute(module, :jido_agent_block_declared, true)

  defp host_config(config, env) do
    if Module.get_attribute(env.module, :jido_agent_combined_extensions) do
      Map.take(config, [:name, :description, :extensions, :vsn])
    else
      unwrap!(Authoring.keys(config, [:name, :description, :vsn, :extensions]), env)
      config
    end
  end

  defp validate_lowered_routes!(routes, lowered, env) do
    lowered = unwrap!(Authoring.routes(lowered), env)

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
    unwrap!(Jido.Agent.__definition_from_module__(module, module.__agent_config__()), env)
    :ok
  end

  defp block_fields(dsl, routes, plugins, env) do
    %{
      schema: Extension.get_opt(dsl, [:agent], :schema, Zoi.object(%{})),
      metadata: Extension.get_opt(dsl, [:agent], :metadata, %{}),
      routes: Enum.map(routes, &lower_route(&1, env)),
      plugins:
        Enum.map(plugins, fn plugin ->
          {plugin.module, unwrap!(Authoring.options(plugin.config), env)}
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

  defp fail!(env, message),
    do: raise(CompileError, file: env.file, line: env.line, description: message)
end
