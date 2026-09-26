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

    fields = block_fields(dsl, routes, plugins, env)
    overlap = Map.keys(fields) |> Enum.filter(&Map.has_key?(config, &1))

    if overlap != [],
      do: fail!(env, "Fields declared in both keyword and block form: #{inspect(overlap)}")

    config =
      Map.merge(
        %{
          description: nil,
          schema: Zoi.object(%{}),
          metadata: %{},
          routes: [],
          plugins: []
        },
        Map.merge(config, fields)
      )

    config = unwrap!(Jido.Agent.Extension.lower(extensions, config, entities), env)
    config = Map.put_new(config, :vsn, 1)

    unless is_integer(config.vsn) and config.vsn > 0 do
      fail!(env, "Agent vsn must be a positive integer")
    end

    routes =
      if extensions == [],
        do: routes,
        else: lowered_interfaces(routes, Map.get(config, :routes, []), env)

    interfaces = interfaces(routes, source, env)

    generated = generate(interfaces, env)
    block? = fields != %{} or source != nil or extensions != []

    quote do
      @doc false
      def __agent_config__, do: unquote(Macro.escape(config))

      unquote_splicing(generated)

      if unquote(block?) do
        @after_verify {Jido.Agent.DSL.Compiler, :verify}
      end
    end
  end

  @doc false
  def register_agent_block!(module),
    do: Module.put_attribute(module, :jido_agent_block_declared, true)

  defp host_config(config, env) do
    if Module.get_attribute(env.module, :jido_agent_combined_extensions) do
      Map.take(config, [:name, :description, :extensions, :vsn])
    else
      config
    end
  end

  defp lowered_interfaces(routes, lowered, env) do
    lowered = unwrap!(Authoring.routes(lowered), env)

    Enum.map(routes, fn route ->
      if route.interfaces == [] do
        route
      else
        case Enum.filter(lowered, &(&1.path == route.path)) do
          [final] when is_nil(final.match) ->
            %{route | target: final.target}

          _ ->
            fail!(
              Authoring.location(env, route),
              "An exposed Signal type must retain exactly one route without a match predicate after lowering"
            )
        end
      end
    end)
  end

  def verify(module) do
    env = %{file: to_string(module.module_info(:compile)[:source]), line: 1}
    unwrap!(Jido.Agent.__definition_from_module__(module, module.__agent_config__()), env)
    :ok
  end

  defp block_fields(dsl, routes, plugins, env) do
    fields =
      Enum.reduce([:schema, :metadata], %{}, fn key, acc ->
        case Extension.fetch_opt(dsl, [:agent], key) do
          {:ok, value} -> Map.put(acc, key, value)
          :error -> acc
        end
      end)

    fields =
      if routes == [],
        do: fields,
        else: Map.put(fields, :routes, Enum.map(routes, &lower_route(&1, env)))

    if plugins == [] do
      fields
    else
      declarations =
        Enum.map(plugins, fn plugin ->
          options = unwrap!(Authoring.options(plugin.config), env)
          {plugin.module, options}
        end)

      Map.put(fields, :plugins, declarations)
    end
  end

  defp lower_route(route, env) do
    opts = [priority: route.priority, match: route.match]
    opts = if is_nil(route.defaults), do: opts, else: Keyword.put(opts, :defaults, route.defaults)
    unwrap!(Authoring.route(route.path, route.target, opts), Authoring.location(env, route))
  end

  defp interfaces(routes, source, env) do
    route_counts = Enum.frequencies_by(routes, & &1.path)

    source_result =
      if Enum.any?(routes, &(&1.interfaces != [])) do
        if is_binary(source),
          do: Jido.Signal.validate_uri_reference(source, []),
          else: :missing
      else
        :ok
      end

    Enum.flat_map(routes, fn route ->
      Enum.map(route.interfaces, fn interface ->
        env = Authoring.location(env, interface)

        if String.contains?(route.path, "*") or route.match != nil,
          do: fail!(env, "define requires an exact route without a match predicate")

        if Map.fetch!(route_counts, route.path) > 1,
          do: fail!(env, "An exposed Signal type must have exactly one route")

        case source_result do
          :ok -> :ok
          :missing -> fail!(env, "signal_source is required for define")
          {:error, reason} -> fail!(env, "Invalid signal_source: #{reason}")
        end

        %{
          name: interface.name,
          path: route.path,
          source: source,
          line: env.line
        }
      end)
    end)
  end

  defp generate(interfaces, env) do
    names = Enum.map(interfaces, & &1.name)
    if length(names) != length(Enum.uniq(names)), do: fail!(env, "Duplicate interface name")

    Enum.map(interfaces, fn interface ->
      name = String.to_atom("#{interface.name}_signal")

      for arity <- [1, 2] do
        if Module.defines?(env.module, {name, arity}),
          do:
            fail!(
              %{env | line: interface.line},
              "Generated function conflicts with #{name}/#{arity}"
            )
      end

      Jido.Agent.DSL.Generator.function(interface)
    end)
  end

  defp extension?(module, callback) when is_atom(module) and not is_nil(module),
    do: Code.ensure_loaded?(module) and function_exported?(module, callback, 2)

  defp extension?(_module, _callback), do: false

  defp unwrap!({:ok, value}, _env), do: value
  defp unwrap!({:error, error}, env), do: fail!(env, Exception.message(error))

  defp fail!(env, message),
    do: raise(CompileError, file: env.file, line: env.line, description: message)
end
