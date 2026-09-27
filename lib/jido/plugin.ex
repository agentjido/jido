defmodule Jido.Plugin do
  @moduledoc """
  Declares one reusable Plugin package and its owner-specific facets.

  A small Plugin declares its roles and implements their callbacks in one module:

      defmodule MyApp.Counter do
        use Jido.Plugin, roles: [:agent]

        @impl true
        def state_spec(_opts), do: {:turns, Zoi.integer() |> Zoi.default(0)}

        @impl true
        def reduce(reduction, _opts), do: {:ok, reduction.plugin_state + 1}
      end

  Roles are `:agent`, `:agent_server`, `:persistence`, and `:topology`. They use
  the callbacks of `Jido.Agent.Plugin`, `Jido.AgentServer.Plugin`,
  `Jido.Persistence.Plugin`, and `Jido.Topology.Plugin`, respectively.
  Jido does not infer roles from function names.

  Larger Plugins can select separate facet modules. Both forms use the same
  manifest, owner Specs, validation, and execution path. A package can combine
  local roles with separate facets for other owners:

      use Jido.Plugin,
        roles: [:agent],
        persistence: MyApp.Counter.Persistence,
        vsn: 1

  Select each owner only once. A package without local roles cannot define
  facet callbacks. A separate facet still implements only its owner's callbacks.

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
  Directive. Once declared, this hook is a required step before Directive
  dispatch. Failure or timeout skips later hooks and Directives and uses the
  Server error policy. It cannot undo the commit or change the result already
  sent to the caller. Startup and replacement use `Jido.Plugin.Init`. Hooks
  are bounded and are not replayed. Use Telemetry for optional observation.
  """

  alias Jido.Plugin.{Init, Manifest, Normalizer}

  @type declaration :: module() | {module(), keyword()}
  @doc "Defines a Plugin package with explicit local roles or separate owner facets."
  defmacro __using__(opts) when is_list(opts) do
    owners = [:agent, :agent_server, :persistence, :topology]
    allowed = owners ++ [:roles, :vsn, :option_keys]
    unknown = Keyword.keys(opts) -- allowed
    roles = Keyword.get(opts, :roles, [])

    unless is_list(roles) and Enum.all?(roles, &(&1 in owners)) and Enum.uniq(roles) == roles do
      raise ArgumentError,
            "Plugin roles must be a literal list of unique owners: #{inspect(owners)}"
    end

    if Enum.any?(roles, &Keyword.has_key?(opts, &1)) do
      raise ArgumentError, "Plugin role cannot also select a separate facet for the same owner"
    end

    behaviours = %{
      agent: Jido.Agent.Plugin,
      agent_server: Jido.AgentServer.Plugin,
      persistence: Jido.Persistence.Plugin,
      topology: Jido.Topology.Plugin
    }

    role_behaviours =
      Enum.map(roles, fn role ->
        quote do
          @behaviour unquote(Map.fetch!(behaviours, role))
        end
      end)

    opts = Enum.reduce(roles, opts, &Keyword.put(&2, &1, __CALLER__.module))

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
      unquote_splicing(role_behaviours)

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
    with {:ok, [spec]} <- Normalizer.normalize_all([declaration]), do: {:ok, spec.manifest}
  end

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

  @doc "Gets the current state owned by one Plugin runtime."
  @spec state(Init.t(), timeout()) :: {:ok, term()} | {:error, term()}
  def state(init, timeout \\ 5_000), do: Jido.AgentServer.Plugin.state(init, timeout)
end
