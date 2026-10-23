defmodule Jido.Agent.DSL do
  @moduledoc false
  alias Jido.Agent.{Error, Extension, Validation}
  alias Spark.Dsl.Extension, as: E

  use Spark.Dsl,
    default_extensions: [extensions: [Jido.Agent.DSL.Extension, Jido.Agent.DSL.Topology]],
    opt_schema: [
      id: [type: :string, required: true],
      name: [type: :string, required: true],
      description: [type: :string],
      vsn: [type: :pos_integer, default: 1]
    ]

  @impl true
  def handle_before_compile(opts) do
    helpers =
      quote unquote: false do
        for route <- @agent_definition.routes, route.as != nil do
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
      @spec schema() :: Zoi.schema()
      def schema, do: Jido.Agent.schema(definition())

      @doc false
      def __jido_authoring__ do
        %{
          id: unquote(opts[:id]),
          kind: :agent,
          vsn: vsn(),
          target: __MODULE__,
          name: @agent_definition.name,
          description: @agent_definition.description
        }
      end

      @doc "Returns the compiled Action target for one inline route or raises when none exists."
      @spec route_action!(String.t()) :: module() | no_return()
      def route_action!(path),
        do: Jido.Action.Inline.target!(__MODULE__, host: Jido.Agent, route: path, role: :action)

      @doc "Runs one pure Agent Turn. It does not commit state or dispatch Directives."
      @spec cmd(Jido.Agent.instance(), Jido.Signal.t(), keyword()) ::
              {:ok, Jido.Agent.instance(), [struct()]} | {:error, term()}
      def cmd(agent, signal, opts \\ []), do: Jido.Agent.cmd(agent, signal, opts)

      @doc "Returns this module's validated neutral Agent definition."
      @spec definition() :: Jido.Agent.definition()
      def definition, do: Jido.Agent.DSL.definition!(@agent_definition)

      @doc "Builds and validates one instance of this Agent."
      @spec instantiate(keyword() | map()) ::
              {:ok, Jido.Agent.instance()} | {:error, term()}
      def instantiate(opts \\ []), do: Jido.Agent.instantiate(__MODULE__, opts)

      @doc "Builds one instance of this Agent or raises its validation error."
      @spec instantiate!(keyword() | map()) :: Jido.Agent.instance() | no_return()
      def instantiate!(opts \\ []), do: Jido.Agent.instantiate!(__MODULE__, opts)
      unquote(helpers)
      @after_verify {Jido.Agent.DSL, :verify!}
    end
  end

  @impl true
  def verify(_module, _opts), do: :ok

  def verify!(module) do
    case Jido.Agent.validate(module.definition()) do
      {:ok, _} -> :ok
      {:error, error} -> raise error
    end
  end

  def definition!(draft) do
    routes =
      Enum.map(draft.routes, fn
        %{handler: %{kind: :executable, target: target}} = route ->
          %{route | handler: Error.unwrap!(Jido.Agent.Route.executable(target))}

        route ->
          route
      end)

    draft |> Map.put(:routes, routes) |> Validation.define(related?: false) |> Error.unwrap!()
  end

  def build!(dsl, opts, module) do
    extensions =
      E.get_persisted(dsl, :spark_extensions, [])
      |> Enum.reject(&(&1 in [Jido.Agent.DSL.Extension, Jido.Agent.DSL.Topology]))

    plugins = E.get_entities(dsl, [:__agent__])
    providers = Enum.uniq(extensions ++ Enum.map(plugins, & &1.provider))

    result =
      with :ok <- Jido.Agent.Data.unique(plugins, & &1.provider),
           {:ok, entries} <-
             Extension.lower(providers, dsl, Map.new(plugins, &{&1.provider, &1.config})) do
        input =
          opts
          |> Keyword.take([:name, :description, :vsn])
          |> Map.new()
          |> Map.merge(%{
            module: module,
            schema: E.get_opt(dsl, [:__agent__], :schema, Zoi.object(%{})),
            metadata: E.get_opt(dsl, [:__agent__], :metadata, %{}),
            signal_source: E.get_opt(dsl, [:__routes__], :signal_source),
            routes:
              Enum.map(
                E.get_entities(dsl, [:__routes__]),
                &Map.take(&1, [:path, :handler, :as, :defaults])
              ),
            topology: Jido.Agent.DSL.Topology.lower(dsl),
            extensions: entries
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
end
