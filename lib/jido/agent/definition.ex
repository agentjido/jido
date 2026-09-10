defmodule Jido.Agent.Definition do
  @moduledoc false

  defmacro __using__(opts) do
    dsl = Keyword.fetch!(opts, :dsl)
    agent_opts = Keyword.fetch!(opts, :agent_options)
    constructors? = Keyword.fetch!(opts, :constructors?)
    combined_extensions? = Keyword.fetch!(opts, :combined_extensions?)

    dsl_opts =
      if is_list(agent_opts) do
        case Keyword.get(agent_opts, :extensions) do
          nil -> []
          extensions -> [extensions: extensions]
        end
      else
        []
      end

    constructors =
      if constructors? do
        quote location: :keep do
          @doc "Creates one Agent instance from this module definition."
          @spec new(map() | keyword()) ::
                  {:ok, Jido.Agent.instance()} | {:error, Exception.t()}
          def new(overrides \\ []) do
            Jido.Agent.instantiate(__MODULE__, overrides)
          end

          @doc "Creates one Agent instance or raises its validation error."
          @spec new!(map() | keyword()) :: Jido.Agent.instance() | no_return()
          def new!(overrides \\ []) do
            Jido.Agent.instantiate!(__MODULE__, overrides)
          end
        end
      end

    quote location: :keep do
      use unquote(dsl), unquote(dsl_opts)
      use Jido.Action.Inline
      @before_compile Jido.Agent.DSL.Compiler
      @behaviour Jido.Agent

      @jido_agent_options unquote(agent_opts)
      @jido_agent_combined_extensions unquote(combined_extensions?)

      @doc "Returns the neutral canonical Agent definition."
      @spec definition() :: Jido.Agent.definition()
      def definition do
        case Jido.Agent.__definition_from_module__(__MODULE__, __agent_config__()) do
          {:ok, definition} -> definition
          {:error, error} -> raise error
        end
      end

      @doc "Returns the Agent name."
      @spec name() :: String.t()
      def name, do: Map.fetch!(__agent_config__(), :name)

      @doc "Returns the Agent description."
      @spec description() :: String.t() | nil
      def description, do: Map.get(__agent_config__(), :description)

      @doc "Returns the positive Agent definition version owned by this module."
      @spec vsn() :: pos_integer()
      def vsn, do: Map.fetch!(__agent_config__(), :vsn)

      @doc "Returns the authored Agent data schema."
      @spec domain_schema() :: Zoi.schema()
      def domain_schema, do: Map.get(__agent_config__(), :schema, Zoi.object(%{}))

      @doc "Returns the authored Agent data schema."
      @spec schema() :: Zoi.schema()
      def schema, do: domain_schema()

      @doc "Returns the complete data schema, including Plugin-owned fields in Agent state."
      @spec complete_schema() :: Zoi.schema()
      def complete_schema, do: Jido.Agent.complete_schema!(definition())

      @doc "Returns the canonical Agent routes."
      @spec routes() :: list()
      def routes, do: definition().routes

      @doc "Returns the Action target compiled for one inline route."
      @spec route_action!(String.t()) :: module()
      def route_action!(path) do
        Jido.Action.Inline.target!(__MODULE__, host: Jido.Agent, route: path, role: :action)
      end

      @doc "Returns the canonical ordered Agent Plugin declarations."
      @spec plugins() :: list()
      def plugins, do: definition().plugins

      @doc "Returns the Agent definition metadata."
      @spec metadata() :: map()
      def metadata, do: definition().metadata

      unquote(constructors)

      @doc "Applies one Signal to an Agent value without starting a Server."
      @spec cmd(Jido.Agent.instance(), Jido.Signal.t(), keyword()) ::
              {:ok, Jido.Agent.instance(), [struct()]} | {:error, term()}
      def cmd(agent, signal, opts \\ []), do: Jido.Agent.cmd(agent, signal, opts)
    end
  end
end
