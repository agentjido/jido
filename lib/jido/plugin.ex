defmodule Jido.Plugin do
  @moduledoc """
  Declares one reusable Plugin package and its owner-specific facets.

  A new Plugin package is callback-free. It names up to one
  `Jido.Agent.Plugin`, `Jido.AgentServer.Plugin`, `Jido.Persistence.Plugin`, and
  `Jido.Topology.Plugin` module:

      defmodule MyApp.Audit do
        use Jido.Plugin,
          agent: MyApp.Audit.Agent,
          persistence: MyApp.Audit.Persistence,
          vsn: 1
      end

  Put common options in the Agent declaration. Use `option_keys` in the
  manifest when facets need different subsets:

      use Jido.Plugin,
        agent: MyApp.Capability.Agent,
        agent_server: MyApp.Capability.Server,
        option_keys: [agent: [:fields], agent_server: [:endpoint]]

  A stateful Agent facet owns one top-level field in the complete
  `Jido.Agent.state` map. Jido does not store Plugin state in a second map.
  Callback fields and accessors named `plugin_state` expose only the selected
  value from that owned Agent field.

  The Agent facet can prepare one portable input and reduce one owned state
  field. The Agent Server facet receives a read-only admission value and can
  return one transient runtime input. Jido exposes the two inputs as
  `context.plugin_inputs[Package].prepared` and
  `context.plugin_inputs[Package].runtime`.

  `use Jido.Plugin` with no manifest options is the mixed-callback compatibility
  form. Its old Directive validation, state update, and Command admission
  callbacks remain for source compatibility. New Plugins must use an
  owner-facet manifest.
  """

  alias Jido.Agent.Command
  alias Jido.Agent.Plugin.Preparation
  alias Jido.Plugin.{DirectiveContext, Init, Manifest, SignalContext, Spec}

  @type declaration :: module() | {module(), keyword()}
  @type state_spec :: :none | {atom(), Zoi.schema()}

  @doc "Defines a Plugin package or the supported mixed compatibility behavior."
  defmacro __using__([]) do
    quote location: :keep do
      @behaviour Jido.Plugin

      @doc false
      def __jido_plugin__, do: :agent
    end
  end

  defmacro __using__(opts) when is_list(opts) do
    allowed = [:agent, :agent_server, :persistence, :topology, :vsn, :option_keys]
    unknown = Keyword.keys(opts) -- allowed

    selected =
      Enum.filter([:agent, :agent_server, :persistence, :topology], &Keyword.has_key?(opts, &1))

    if unknown != [] do
      raise ArgumentError,
            "use Jido.Plugin does not accept options without owner facets; unknown manifest options: #{inspect(unknown)}"
    end

    if selected == [] do
      raise ArgumentError, "use Jido.Plugin manifest must select at least one facet"
    end

    agent = Keyword.get(opts, :agent)
    agent_server = Keyword.get(opts, :agent_server)
    persistence = Keyword.get(opts, :persistence)
    topology = Keyword.get(opts, :topology)
    vsn = Keyword.get(opts, :vsn, 1)
    option_keys = Keyword.get(opts, :option_keys, [])

    quote location: :keep do
      @doc false
      def __jido_plugin__ do
        %Jido.Plugin.Manifest{
          module: __MODULE__,
          agent: unquote(agent),
          agent_server: unquote(agent_server),
          persistence: unquote(persistence),
          topology: unquote(topology),
          vsn: unquote(vsn),
          option_keys: Map.new(unquote(option_keys))
        }
      end
    end
  end

  @callback validate_options(opts :: keyword()) ::
              :ok | {:ok, keyword()} | {:error, term()}
  @callback prepare(preparation :: Preparation.t(), opts :: keyword()) ::
              {:ok, term()} | {:error, term()}
  @callback admit(runtime_ref :: term() | nil, command :: Command.t(), opts :: keyword()) ::
              {:ok, Command.t()} | {:error, term()}
  @callback prepare_dispatch(
              runtime_ref :: term() | nil,
              signal :: Jido.Signal.t(),
              context :: SignalContext.t(),
              opts :: keyword()
            ) :: {:ok, Jido.Signal.t()} | {:error, term()}
  @callback state_spec(opts :: keyword()) :: state_spec()
  @callback update_state(plugin_state :: term(), directives :: [struct()], opts :: keyword()) ::
              {:ok, plugin_state :: term()} | {:error, term()}
  @callback directives(opts :: keyword()) :: [module()] | {:error, term()}
  @callback validate_directive(directive :: struct(), opts :: keyword()) ::
              {:ok, struct()} | {:error, term()}
  @callback dispatch(
              runtime_ref :: term() | nil,
              directive :: struct(),
              context :: DirectiveContext.t(),
              opts :: keyword()
            ) :: :ok | {:error, term()}
  @callback await_ready(runtime_ref :: term(), opts :: keyword()) :: :ok | {:error, term()}

  @optional_callbacks validate_options: 1,
                      prepare: 2,
                      admit: 3,
                      prepare_dispatch: 4,
                      state_spec: 1,
                      update_state: 3,
                      directives: 1,
                      validate_directive: 2,
                      dispatch: 4,
                      await_ready: 2

  @doc "Normalizes one declaration and returns its static manifest."
  @spec manifest(declaration()) :: {:ok, Manifest.t()} | {:error, term()}
  def manifest(declaration) do
    with {:ok, [spec]} <- normalize_all([declaration]), do: {:ok, spec.manifest}
  end

  @doc false
  @spec normalize_all([declaration()] | [Spec.t()]) :: {:ok, [Spec.t()]} | {:error, term()}
  defdelegate normalize_all(declarations), to: Jido.Plugin.Normalizer

  @doc false
  @spec canonical_declarations([declaration()] | [Spec.t()]) ::
          {:ok, [{module(), keyword()}]} | {:error, term()}
  defdelegate canonical_declarations(declarations), to: Jido.Plugin.Normalizer

  @doc false
  defdelegate compose_schema(schema, declarations), to: Jido.Agent.Plugin

  @doc false
  defdelegate prepares?(specs), to: Jido.Agent.Plugin

  @doc false
  defdelegate prepare(agent, signal, specs), to: Jido.Agent.Plugin

  @doc false
  def directive_owner(specs, %{__struct__: directive_module}) when is_list(specs) do
    Enum.find(specs, fn
      %{agent: %Jido.Agent.Plugin.Spec{directive_modules: modules}} ->
        directive_module in modules

      _spec ->
        false
    end)
  end

  def directive_owner(_specs, _directive), do: nil

  @doc false
  def validate_directive(%Jido.Plugin.Spec{agent: agent_spec}, directive) do
    Jido.Agent.Plugin.validate_legacy_directive(agent_spec, directive)
  end

  @doc false
  defdelegate admits?(specs), to: Jido.AgentServer.Plugin

  @doc false
  defdelegate admission_modules(specs), to: Jido.AgentServer.Plugin

  @doc false
  defdelegate dispatch_modules(specs), to: Jido.AgentServer.Plugin

  @doc false
  defdelegate admit(command, specs, runtime_refs), to: Jido.AgentServer.Plugin

  @doc false
  defdelegate admit(command, specs, runtime_refs, state_version), to: Jido.AgentServer.Plugin

  @doc false
  defdelegate prepare_dispatch(signal, specs, runtime_refs, context, agent_state),
    to: Jido.AgentServer.Plugin

  @doc false
  @spec child_specs(Init.t(), [declaration()] | [Spec.t()]) ::
          {:ok, [Supervisor.child_spec()]} | {:error, term()}
  defdelegate child_specs(init, declarations), to: Jido.AgentServer.Plugin

  @doc "Gets the current state owned by one Plugin runtime."
  @spec state(Init.t(), timeout()) :: {:ok, term()} | {:error, term()}
  def state(init, timeout \\ 5_000), do: Jido.AgentServer.Plugin.state(init, timeout)

  @doc false
  defdelegate dispatch(spec, runtime_ref, directive, context), to: Jido.AgentServer.Plugin

  @doc false
  defdelegate await_ready(spec, runtime_ref), to: Jido.AgentServer.Plugin
end
