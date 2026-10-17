defmodule Jido.Agent.Authoring.Compiler do
  @moduledoc false

  alias Jido.Agent.Authoring
  alias Jido.Agent.Authoring.SourceMap
  alias Jido.Agent.DSL.Schedules, as: ScheduleDSL
  alias Spark.Dsl.Extension

  @agent_root_options [:name, :description, :vsn]

  defmacro __using__(opts) do
    agent_opts = Keyword.fetch!(opts, :agent_options)

    quote location: :keep do
      @jido_agent_options Jido.Agent.Authoring.Compiler.options!(unquote(agent_opts), __ENV__)
      Jido.Agent.Authoring.Compiler.setup_dsl(__ENV__, Jido.Agent.DSL, @jido_agent_options)
      import Jido.Agent.Authoring.Compiler, only: [agent: 1, routes: 1, topology: 1, schedules: 1]
      unquote_splicing(extension_imports(agent_opts, __CALLER__))
      use Jido.Action.Inline
      @before_compile Jido.Agent.Authoring.Compiler
      @behaviour Jido.Agent

      @doc "Returns the neutral canonical Agent definition."
      @spec definition() :: Jido.Agent.definition()
      def definition, do: Jido.Agent.Authoring.unwrap!(Jido.Agent.Source.definition(__MODULE__))

      @doc "Returns the positive Agent definition version owned by this module."
      @spec vsn() :: pos_integer()
      def vsn, do: __agent_config__().vsn

      @doc "Returns the authored Agent data schema."
      @spec domain_schema() :: Zoi.schema()
      def domain_schema, do: __agent_config__().schema

      @doc "Returns the complete data schema, including Plugin-owned fields in Agent state."
      @spec complete_schema() :: Zoi.schema()
      def complete_schema do
        case Jido.Agent.Source.definition_with_plugins(__MODULE__) do
          {:ok, _definition, _specs, schema} -> schema
          {:error, error} -> raise error
        end
      end

      @doc "Returns the Action target compiled for one inline route."
      @spec route_action!(String.t()) :: module()
      def route_action!(path) do
        Jido.Action.Inline.target!(__MODULE__, host: Jido.Agent, route: path, role: :action)
      end

      @doc "Applies one Signal to an Agent value without starting a Server."
      @spec cmd(Jido.Agent.instance(), Jido.Signal.t(), keyword()) ::
              {:ok, Jido.Agent.instance(), [struct()]} | {:error, term()}
      def cmd(agent, signal, opts \\ []), do: Jido.Agent.cmd(agent, signal, opts)
    end
  end

  def options!(value, env), do: unwrap!(Authoring.attrs(value), env)

  # Evaluate options in the module body, after its attributes exist. Spark needs
  # literal options when it expands, so install it in this evaluated scope.
  def setup_dsl(env, dsl, options) do
    extensions = Map.get(options, :extensions, [])

    {_, _, configured_env} =
      Code.eval_quoted_with_env(
        quote(do: use(unquote(dsl), extensions: unquote(Macro.escape(extensions)))),
        [],
        env
      )

    imports =
      for key <- [:functions, :macros, :requires], into: %{} do
        {key, Map.fetch!(configured_env, key) -- Map.fetch!(env, key)}
      end

    Module.put_attribute(env.module, :jido_dsl_imports, imports)

    :ok
  end

  def eval_block(env, name, body, bindings) do
    imports = Module.get_attribute(env.module, :jido_dsl_imports)

    env = %{
      env
      | functions: Keyword.merge(env.functions, imports.functions),
        macros: env.macros |> Keyword.merge(imports.macros) |> Keyword.delete(__MODULE__),
        requires: Enum.uniq(env.requires ++ imports.requires)
    }

    Code.eval_quoted(
      {name, [line: env.line], [[do: body]]},
      bindings,
      env
    )

    :ok
  end

  # Keep extension-owned root sections available for literal extension options.
  defp extension_imports(options, env) do
    extensions =
      case options do
        {:%{}, _, entries} -> Keyword.get(entries, :extensions, [])
        entries when is_list(entries) -> Keyword.get(entries, :extensions, [])
        _ -> []
      end

    if is_list(extensions) do
      extensions =
        extensions
        |> Enum.map(fn
          {:__aliases__, _, _} = alias -> Macro.expand(alias, env)
          value -> value
        end)
        |> Enum.filter(&(is_atom(&1) and not is_nil(&1)))

      # Spark root macros read this attribute during expansion. The evaluated
      # setup later installs the complete extension set, including defaults.
      Module.put_attribute(env.module, :extensions, extensions)

      extensions
      |> Spark.Dsl.Extension.prepare()
      |> Enum.flat_map(fn
        {:__block__, _, forms} -> forms
        form -> [form]
      end)
      |> Enum.filter(fn
        {:import, _, _} -> true
        {:require, _, _} -> true
        _ -> false
      end)
    else
      []
    end
  end

  # Expand blocks after the module body has evaluated the options. Spark owns
  # the block contents and supplies the imports captured during setup.
  for name <- [:agent, :routes, :topology, :schedules] do
    defmacro unquote(name)(do: body) do
      name = unquote(name)

      quote do
        Jido.Agent.Authoring.Compiler.eval_block(
          __ENV__,
          unquote(name),
          unquote(Macro.escape(body)),
          binding()
        )
      end
    end
  end

  defmacro __before_compile__(env) do
    options = Module.get_attribute(env.module, :jido_agent_options)
    {extensions, options} = Map.pop(options, :extensions, [])
    {agent_extensions, topology_extensions} = extensions(extensions, env)
    unwrap!(Authoring.keys(options, @agent_root_options), env)
    # Read current compile state once. Loaded module code can be stale on reload.
    dsl = Module.get_attribute(env.module, :spark_dsl_config) || %{}
    {topology, sources} = Jido.Agent.DSL.Topology.lower(topology_extensions, dsl, env)

    agent =
      lower_agent(Map.put(options, :topology, topology), agent_extensions, dsl, env, sources)

    quote do
      unquote(agent)
      @after_verify {Jido.Agent.Authoring.Compiler, :verify}
    end
  end

  defp lower_agent(config, extensions, dsl, env, topology_sources) do
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

    sources = Map.merge(sources(dsl, routes, plugins), topology_sources)

    config =
      config
      |> Map.put_new(:description, nil)
      |> Map.merge(block_fields(dsl, routes, plugins, env, sources))

    config = unwrap!(Jido.Agent.Extension.lower(extensions, config, entities), env, sources)

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

  defp extensions(extensions, env) do
    {agent, topology} = partition_extensions(extensions, {[], []}, env)
    {Enum.reverse(agent), Enum.reverse(topology)}
  end

  defp partition_extensions([], partition, _env), do: partition

  defp partition_extensions([extension | rest], {agent, topology}, env) do
    loaded? = is_atom(extension) and not is_nil(extension) and Code.ensure_loaded?(extension)
    agent? = loaded? and function_exported?(extension, :lower_agent, 2)
    topology? = loaded? and function_exported?(extension, :lower_topology, 2)

    unless agent? or topology?,
      do: fail!(env, "Authoring extension must implement lower_agent/2 or lower_topology/2")

    partition_extensions(
      rest,
      {if(agent?, do: [extension | agent], else: agent),
       if(topology?, do: [extension | topology], else: topology)},
      env
    )
  end

  defp partition_extensions(_tail, _partition, env),
    do: fail!(env, "Expected a proper list")

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

    :ok
  end

  defp sources(dsl, routes, plugins) do
    locations = SourceMap.section(dsl, [:agent], [:schema, :metadata], [])
    locations = Map.merge(locations, SourceMap.section(dsl, [:agent], [], [:plugins]))

    locations = Map.merge(locations, SourceMap.section(dsl, [:schedules], [], [:schedules]))

    SourceMap.collect(
      [routes: routes, plugins: plugins, schedules: Extension.get_entities(dsl, [:schedules])],
      locations
    )
  end

  defp block_fields(dsl, routes, plugins, env, sources) do
    %{
      schema: Extension.get_opt(dsl, [:agent], :schema, Zoi.object(%{})),
      metadata: Extension.get_opt(dsl, [:agent], :metadata, %{}),
      routes: Enum.map(routes, &lower_route(&1, env)),
      schedules: ScheduleDSL.lower(dsl),
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

      signal_function(name, route.path, source)
    end)
  end

  @doc false
  def unwrap!(:ok, _env), do: :ok
  def unwrap!({:ok, value}, _env), do: value

  def unwrap!({:error, error}, env), do: fail!(env, Exception.message(error))

  @doc false
  def unwrap!({:ok, value}, _env, _sources), do: value

  def unwrap!({:error, error}, env, sources) do
    line = SourceMap.lookup(sources, Map.get(error.details || %{}, :source_path, []), env.line)
    fail!(%{env | line: line}, Exception.message(error))
  end

  @doc false
  def fail!(env, message),
    do: raise(CompileError, file: env.file, line: env.line, description: message)

  defp signal_function(name, path, source) do
    quote do
      @doc """
      Builds a `#{unquote(path)}` Signal from a plain input map.

      Returns `{:ok, signal}` or `{:error, reason}`. Envelope options include
      `:source`, `:id`, and `:subject`. Unknown or duplicate options are errors.
      Options cannot replace Signal type or data.

      Omitted input fields remain absent. Route defaults supply absent fields
      during execution. Explicit `nil`, `false`, and zero override defaults.
      The Action or Flow validates input during command execution.
      This function does not execute a command. Use `Jido.Agent.cmd/3` for
      direct execution or `Jido.AgentServer.call/3` for a live Server.
      """
      @spec unquote(name)(map(), keyword()) :: {:ok, Jido.Signal.t()} | {:error, term()}
      def unquote(name)(input, envelope_opts \\ []),
        do:
          Jido.Agent.Interface.signal(
            %{path: unquote(path), source: unquote(source)},
            input,
            envelope_opts
          )
    end
  end

  @doc false
  def validate_schema_storage(value) do
    Macro.escape(value)
    {:ok, value}
  rescue
    ArgumentError -> {:error, "Schema contains values that cannot be stored in a module"}
  end
end
