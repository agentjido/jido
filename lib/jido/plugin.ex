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

  The Server facet can also implement `after_commit/3` to keep a live view of
  its exact committed owned value and revision, without an Action-owned
  Directive. Startup and replacement use `Jido.Plugin.Init`; notifications
  are bounded, best effort, and not replayed.

  Every Plugin must use an owner-facet manifest. Package modules do not define
  lifecycle callbacks.
  """

  alias Jido.Plugin.{Init, Manifest, Spec}

  @type declaration :: module() | {module(), keyword()}
  @doc "Defines a Plugin package with one or more owner facets."
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
