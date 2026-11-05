defmodule Jido.Agent.DSL do
  alias Jido.Joi
  @moduledoc false
  alias Jido.Agent.{Extension, Validation}
  alias Jido.Error
  alias Spark.Dsl.Extension, as: E

  use Spark.Dsl,
    many_extension_kinds: [:plugin_providers],
    untyped_extensions?: false,
    default_extensions: [
      plugin_providers: [Jido.Agent.DSL.Extension, Jido.Agent.DSL.Topology]
    ],
    opt_schema: [
      id: [type: :string, required: true],
      name: [type: :string, required: true],
      description: [type: :string],
      vsn: [type: :pos_integer, default: 1],
      metadata: [type: :any],
      plugin_declarations: [type: :any, default: []]
    ]

  @impl true
  def handle_before_compile(opts) do
    helpers =
      quote unquote: false do
        for route <- @agent_definition.routes,
            route.as != nil and not Jido.Agent.Schema.wildcard?(route.path) do
          helper = String.to_atom(Atom.to_string(route.as) <> "_signal")
          bang_helper = String.to_atom(Atom.to_string(route.as) <> "_signal!")

          @doc "Builds an input Signal without target validation or execution."
          @spec unquote(helper)(map(), keyword() | map()) ::
                  {:ok, Jido.Signal.t()} | {:error, term()}
          def unquote(helper)(data \\ %{}, opts \\ []),
            do: Jido.Agent.input_signal(@agent_definition, unquote(route.path), data, opts)

          @doc "Builds an input Signal or raises for an invalid Signal input. It does not validate or run the target."
          @spec unquote(bang_helper)(map(), keyword() | map()) :: Jido.Signal.t() | no_return()
          def unquote(bang_helper)(data \\ %{}, opts \\ []),
            do: Jido.Agent.input_signal!(@agent_definition, unquote(route.path), data, opts)
        end
      end

    quote do
      @agent_definition Jido.Agent.DSL.build!(
                          @spark_dsl_config,
                          unquote(Macro.escape(opts)),
                          __MODULE__
                        )
      @behaviour Jido.Agent

      @doc "Returns this Agent definition version."
      @spec vsn() :: pos_integer()
      def vsn, do: @agent_definition.vsn

      @doc "Returns the complete state schema, including Plugin-owned fields."
      @spec schema() :: Joi.schema()
      def schema, do: Jido.Agent.schema(definition())

      @doc false
      def __jido_catalog_manifest__ do
        %{
          id: unquote(opts[:id]),
          kind: :agent,
          vsn: vsn(),
          target: __MODULE__,
          name: @agent_definition.name,
          description: @agent_definition.description
        }
      end

      @doc "Returns the Action or Flow target for one exact executable route."
      @spec route_executable!(String.t()) :: module() | no_return()
      def route_executable!(path) do
        case Enum.find(@agent_definition.routes, &(&1.path == path)) do
          %{handler: %{kind: :executable, target: target}} ->
            %{target: target} = Jido.Agent.Route.executable(target) |> Jido.Error.unwrap!()

            target

          %{handler: %{kind: kind, target: target}} when kind in [:action, :flow] ->
            target

          _route ->
            raise ArgumentError,
                  "unknown executable route in #{inspect(__MODULE__)}: #{inspect(path)}"
        end
      end

      @doc "Runs one pure Agent Turn. It does not commit state or dispatch Directives."
      @spec cmd(Jido.Agent.instance(), Jido.Signal.t(), keyword()) ::
              {:ok, Jido.Agent.instance(), [struct()]} | {:error, term()}
      def cmd(agent, signal, opts \\ []), do: Jido.Agent.cmd(agent, signal, opts)

      @doc "Returns this module's validated neutral Agent definition."
      @spec definition() :: Jido.Agent.definition()
      def definition, do: Jido.Agent.DSL.definition!(@agent_definition)

      @doc false
      def __jido_definition__(opts), do: Jido.Agent.DSL.definition(@agent_definition, opts)

      @doc "Builds and validates one instance of this Agent."
      @spec instantiate(keyword() | map()) ::
              {:ok, Jido.Agent.instance()} | {:error, term()}
      def instantiate(opts \\ []), do: Jido.Agent.instantiate(__MODULE__, opts)

      @doc "Builds one instance of this Agent or raises its validation error."
      @spec instantiate!(keyword() | map()) :: Jido.Agent.instance() | no_return()
      def instantiate!(opts \\ []), do: Jido.Agent.instantiate!(__MODULE__, opts)
      unquote(helpers)
      @doc false
      def __jido_location__, do: {__ENV__.file, __ENV__.line}
      @after_verify {Jido.Agent.DSL, :verify!}
    end
  end

  @impl true
  def verify(_module, _opts), do: :ok

  def verify!(module) do
    case Jido.Agent.validate(module.definition()) do
      {:ok, _} -> :ok
      {:error, error} -> compile_error!(module, error)
    end
  rescue
    error in Error.ValidationError -> compile_error!(module, error)
  end

  # Elixir runs @after_verify after compilation, so report the source location here.
  defp compile_error!(module, error) do
    {file, line} = module.__jido_location__()

    raise CompileError,
      file: file,
      line: line,
      description:
        "#{inspect(module)}: #{Exception.message(error)} " <>
          "(code: #{inspect(Map.get(error, :code))}, path: #{inspect(Map.get(error, :path))}, " <>
          "details: #{inspect(Map.get(error, :details))})"
  end

  @doc false
  @spec prepend_plugin(keyword(), Jido.Plugin.declaration()) :: keyword()
  def prepend_plugin(options, plugin) do
    options = validate_keyword!(options)
    plugins = Keyword.get(options, :plugins, [])

    unless is_list(plugins), do: raise(ArgumentError, "Agent plugins must be a list")

    plugins = if plugin in plugins, do: plugins, else: [plugin | plugins]

    Keyword.delete(options, :plugins) ++ [plugins: plugins]
  end

  def definition!(draft), do: draft |> definition(related?: true) |> Error.unwrap!()

  @doc false
  def definition(draft, opts) do
    routes =
      Enum.map(draft.routes, fn
        %{handler: %{kind: :executable, target: target}} = route ->
          %{route | handler: Error.unwrap!(Jido.Agent.Route.executable(target))}

        route ->
          route
      end)

    draft |> Map.put(:routes, routes) |> Validation.define(opts)
  end

  def build!(dsl, opts, module) do
    result =
      with {:ok, entries} <- Extension.lower(opts[:plugin_declarations], dsl) do
        input =
          opts
          |> Keyword.take([:name, :description, :vsn, :metadata])
          |> Map.new()
          |> Map.merge(%{
            module: module,
            schema: E.get_opt(dsl, [:__state__], :schema, Joi.object(%{})),
            initial_state: E.get_opt(dsl, [:__state__], :initial_state, %{}),
            signal_source: E.get_opt(dsl, [:__routes__], :signal_source),
            routes:
              Enum.map(
                E.get_entities(dsl, [:__routes__]),
                &Map.take(&1, [:path, :handler, :state, :reply, :as, :defaults])
              ),
            topology: Jido.Agent.DSL.Topology.lower(dsl),
            plugins: entries
          })

        Validation.define(input, related?: false)
      end

    case result do
      {:ok, definition} ->
        definition

      {:error, error} ->
        raise Spark.Error.DslError,
          module: module,
          path: error.path,
          message: Exception.message(error)
    end
  end

  defp validate_keyword!(options) do
    unless Keyword.keyword?(options) and Enum.uniq(Keyword.keys(options)) == Keyword.keys(options),
      do: raise(ArgumentError, "Agent requires unique keyword options")

    options
  end
end
