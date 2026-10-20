defmodule Jido.Agent.DSL do
  @moduledoc false
  alias Jido.Agent.{Error, Extension, Validation}
  alias Spark.Dsl.Extension, as: E

  use Spark.Dsl,
    default_extensions: [extensions: [Jido.Agent.DSL.Extension, Jido.Agent.DSL.Topology]],
    opt_schema: [
      name: [type: :string, required: true],
      description: [type: :string],
      vsn: [type: :pos_integer, default: 1],
      plugin_providers: [type: {:list, :atom}, default: []]
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
      def vsn, do: @agent_definition.vsn
      def schema, do: Jido.Agent.schema(definition())

      def route_action!(path),
        do: Jido.Action.Inline.target!(__MODULE__, host: Jido.Agent, route: path, role: :action)

      def cmd(agent, signal, opts \\ []), do: Jido.Agent.cmd(agent, signal, opts)
      def definition, do: Jido.Agent.DSL.definition!(@agent_definition)
      def instantiate(opts \\ []), do: Jido.Agent.instantiate(__MODULE__, opts)
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
    providers =
      E.get_persisted(dsl, :spark_extensions, [])
      |> Enum.reject(&(&1 in [Jido.Agent.DSL.Extension, Jido.Agent.DSL.Topology]))

    plugins = E.get_entities(dsl, [:__agent__])

    result =
      with :ok <- Jido.Agent.Data.unique(plugins, & &1.provider),
           :ok <- plugin_registration(plugins, opts[:plugin_providers]),
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
                &Map.take(&1, [:path, :handler, :as, :defaults, :emits])
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

  defp plugin_registration(plugins, discovered) do
    actual = Enum.map(plugins, & &1.provider)

    if actual == discovered,
      do: :ok,
      else:
        Error.fail(
          :plugin_discovery,
          [:agent],
          "Plugin DSL discovery needs a source file with literal provider aliases; use extensions: for generated modules"
        )
  end
end
