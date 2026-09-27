defmodule Jido.Plugin do
  @moduledoc """
  Defines one reusable Plugin through optional callbacks.

      defmodule MyApp.Counter do
        use Jido.Plugin

        @impl true
        def state_spec(_opts), do: {:turns, Zoi.integer() |> Zoi.default(0)}

        @impl true
        def reduce(reduction, _opts), do: {:ok, reduction.plugin_state + 1}
      end

  Implement only the documented callbacks that the Plugin needs. Jido selects
  capabilities from these callbacks at compile time. No roles or separate facet
  modules are required. A large Plugin can delegate work to ordinary modules.

  Core keeps callback ownership and execution order. Agent callbacks prepare
  portable input and reduce one owned field in the complete Agent state.
  Agent Server callbacks admit live input, manage a supervised runtime, and
  run work after commit. Persistence callbacks convert the owned state value.
  Topology callbacks contribute to a plan without starting processes.

  Configure a Plugin with `{MyApp.Counter, options}` in the Agent declaration.
  Each callback receives those options. The optional `option_keys` mapping can
  restrict options by owner when needed. Use `vsn` to set the stored Plugin
  version; it defaults to 1.

  A reducer requires `state_spec/1`. Persistence requires an owned state field
  and both `dump/3` and `load/3`. Runtime dispatch requires owned Directives.
  Jido validates these contracts when it normalizes the declaration.

  Prepared and live inputs remain separate:
  `context.plugin_inputs[MyApp.Counter].prepared` and
  `context.plugin_inputs[MyApp.Counter].runtime`.
  `after_commit/3` is a required step before Directive dispatch when defined.
  """

  alias Jido.Plugin.{Init, Manifest, Normalizer}

  @type declaration :: module() | {module(), keyword()}
  @type state_spec :: :none | {atom(), Zoi.schema()}

  @callback prepare(Jido.Agent.Plugin.Preparation.t(), keyword()) ::
              {:ok, term()} | {:error, term()}
  @callback state_spec(keyword()) :: state_spec() | {:error, term()}
  @callback directives(keyword()) :: [module()] | {:error, term()}
  @callback reduce(Jido.Agent.Plugin.Reduction.t(), keyword()) :: {:ok, term()} | {:error, term()}
  @callback validate_options(keyword()) :: :ok | {:error, term()}
  @callback admit(term() | nil, Jido.AgentServer.Plugin.Admission.t(), keyword()) ::
              {:ok, term()} | {:error, term()}
  @callback prepare_dispatch(
              term() | nil,
              Jido.Signal.t(),
              Jido.Plugin.SignalContext.t(),
              keyword()
            ) ::
              {:ok, Jido.Signal.t()} | {:error, term()}
  @callback dispatch(term() | nil, struct(), Jido.Plugin.DirectiveContext.t(), keyword()) ::
              :ok | {:error, term()}
  @callback child_spec(Init.t()) :: Supervisor.child_spec()
  @callback await_ready(term(), keyword()) :: :ok | {:error, term()}

  @doc """
  Runs after a successful Turn commit and before Directive dispatch.

  Hooks run in declaration order, including commits with unchanged state.
  The callback receives its exact committed owned value and revision. It cannot
  replace state or return Directives. Startup, restore, and direct Agent
  commands do not invoke it.

  Agent Server runs each hook in an owned task with the finite
  `directive_timeout`, or 5,000 milliseconds when that option is `:infinity`.
  Failure or timeout skips later hooks and Directives and uses the Server error
  policy. The commit and the result already sent to the caller stay intact.
  Hooks are not replayed. Rebuild live state from `Jido.Plugin.Init` on startup
  and runtime replacement. Use Telemetry for optional observation.
  """
  @callback after_commit(term() | nil, Jido.AgentServer.Plugin.Commit.t(), keyword()) ::
              :ok | {:error, term()}
  @callback dump(term(), Jido.Persistence.Plugin.Context.t(), keyword()) ::
              {:ok, term()} | {:error, term()}
  @callback load(term(), Jido.Persistence.Plugin.Context.t(), keyword()) ::
              {:ok, term()} | {:error, term()}
  @callback contribute(Jido.Topology.Plugin.Context.t(), keyword()) ::
              {:ok, Jido.Topology.Plugin.Contribution.t()} | {:error, term()}

  @owner_callbacks [
    agent: [prepare: 2, state_spec: 1, directives: 1, reduce: 2],
    agent_server: [
      validate_options: 1,
      admit: 3,
      prepare_dispatch: 4,
      dispatch: 4,
      child_spec: 1,
      await_ready: 2,
      after_commit: 3
    ],
    persistence: [dump: 3, load: 3],
    topology: [contribute: 2]
  ]
  @optional_callbacks Enum.flat_map(@owner_callbacks, &elem(&1, 1))

  @doc false
  def owner_callbacks, do: @owner_callbacks

  @doc "Defines a Plugin. Implement only the callbacks it needs."
  defmacro __using__(opts) do
    unless is_list(opts) and Keyword.keyword?(opts) do
      raise ArgumentError, "use Jido.Plugin options must be a keyword list"
    end

    unknown = Keyword.keys(opts) -- [:vsn, :option_keys]

    if unknown != [] do
      raise ArgumentError,
            "use Jido.Plugin does not accept options #{inspect(unknown)}; " <>
              "define callbacks in the Plugin module without roles or facet selectors"
    end

    quote location: :keep do
      @behaviour Jido.Plugin
      @before_compile Jido.Plugin
      @jido_plugin_vsn unquote(Keyword.get(opts, :vsn, 1))
      @jido_plugin_option_keys Map.new(unquote(Keyword.get(opts, :option_keys, [])))
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    owners =
      for {owner, callbacks} <- @owner_callbacks do
        selected = Enum.any?(callbacks, &Module.defines?(env.module, &1, :def))
        {owner, if(selected, do: env.module)}
      end

    quote do
      @doc false
      def __jido_plugin__ do
        struct!(
          Jido.Plugin.Manifest,
          unquote(owners) ++
            [
              module: __MODULE__,
              vsn: @jido_plugin_vsn,
              option_keys: @jido_plugin_option_keys
            ]
        )
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
