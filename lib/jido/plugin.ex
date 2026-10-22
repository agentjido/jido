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

  Configure a Plugin in the Agent DSL with `plugin MyApp.Counter, config: %{}`.
  Map definitions store the same data once in the `extensions` contribution list.
  A Plugin uses the Agent provider contract and can add Spark sections. Set `id`
  to give the provider a stable name and `vsn` to set its version (default 1).
  Runtime callbacks receive config as keyword options. The optional `option_keys`
  mapping can restrict those options by owner.

  A reducer requires `state_spec/1`. Persistence requires an owned state field
  and both `dump/3` and `load/3`. Runtime dispatch requires owned Directives.
  Jido validates these contracts when it normalizes the declaration.

  Prepared and live inputs remain separate:
  `context.plugin_inputs[MyApp.Counter].prepared` and
  `context.plugin_inputs[MyApp.Counter].runtime`.
  `after_commit/3` is a required step before Directive dispatch when defined.

  A live options change or removal requires runtime Plugins to implement both
  `quiesce/2` and `resume/2`. These callbacks must be idempotent. Quiescence must
  stop autonomous changes and drain outstanding work before it returns. Resume
  must also be safe when quiescence did not finish. The old root remains paused
  through save. Reconciliation replaces it from the accepted state and options.
  On pre-commit rejection or cancellation, resume reopens the old root. A storage
  failure stops the Activation. Changed Plugins do not receive `after_commit/3`
  for the configuration commit; unchanged Plugins keep their normal hooks.
  """

  alias Jido.Plugin.Init

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

  @doc "Pauses autonomous work before a live Plugin change. Must be idempotent."
  @callback quiesce(term(), keyword()) :: :ok | {:error, term()}
  @doc "Resumes a paused Plugin after a rejected change. Must be idempotent."
  @callback resume(term(), keyword()) :: :ok | {:error, term()}

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

  @owner_callbacks [
    agent: [prepare: 2, state_spec: 1, directives: 1, reduce: 2],
    agent_server: [
      validate_options: 1,
      admit: 3,
      prepare_dispatch: 4,
      dispatch: 4,
      child_spec: 1,
      await_ready: 2,
      quiesce: 2,
      resume: 2,
      after_commit: 3
    ],
    persistence: [dump: 3, load: 3]
  ]
  @optional_callbacks Enum.flat_map(@owner_callbacks, &elem(&1, 1))
  @use_options [:vsn, :option_keys, :id, :sections]

  @doc false
  def owner_callbacks, do: @owner_callbacks

  @doc "Defines a Plugin. Implement only the callbacks it needs."
  defmacro __using__(opts) do
    opts = validate_use_options!(opts)
    option_keys = normalize_option_keys!(Keyword.get(opts, :option_keys, []))

    quote location: :keep do
      use Jido.Agent.Extension,
        id: unquote(Keyword.get(opts, :id, Atom.to_string(__CALLER__.module))),
        vsn: unquote(Keyword.get(opts, :vsn, 1)),
        kind: :plugin,
        sections: unquote(Keyword.get(opts, :sections, []))

      def runtime_support, do: __MODULE__

      def normalize(data) do
        with :ok <- Jido.Agent.Data.plain_map(data),
             :ok <- Jido.Agent.Data.static(data),
             do: {:ok, data}
      end

      # Agent schema composition validates Plugin contracts once per boundary.
      def verify(_data, _definition), do: :ok

      defoverridable runtime_support: 0, normalize: 1, verify: 2
      @behaviour Jido.Plugin
      @before_compile Jido.Plugin
      @jido_plugin_vsn unquote(Keyword.get(opts, :vsn, 1))
      @jido_plugin_option_keys unquote(Macro.escape(option_keys))
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

  @doc false
  @spec directive_owner([Jido.Plugin.Spec.t()], struct()) :: Jido.Plugin.Spec.t() | nil
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

  defp validate_use_options!(opts) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError, "use Jido.Plugin options must be a keyword list"
    end

    keys = Keyword.keys(opts)

    if Enum.uniq(keys) != keys do
      raise ArgumentError, "use Jido.Plugin options must be unique"
    end

    unknown = keys -- @use_options

    if unknown != [] do
      raise ArgumentError,
            "use Jido.Plugin does not accept options #{inspect(unknown)}; " <>
              "define callbacks in the Plugin module without roles or facet selectors"
    end

    opts
  end

  defp normalize_option_keys!(value) do
    if Keyword.keyword?(value) do
      owners = Keyword.keys(value)

      if Enum.uniq(owners) != owners do
        raise ArgumentError, "use Jido.Plugin option owners must be unique"
      end

      validate_option_keys!(value, value)
    else
      invalid_option_keys!(value)
    end
  end

  defp validate_option_keys!(entries, source) do
    owners = Keyword.keys(@owner_callbacks)

    valid? =
      Enum.all?(entries, fn {owner, keys} ->
        owner in owners and is_list(keys) and Enum.all?(keys, &is_atom/1) and
          Enum.uniq(keys) == keys
      end)

    if valid?, do: Map.new(entries), else: invalid_option_keys!(source)
  end

  defp invalid_option_keys!(value) do
    raise ArgumentError,
          "use Jido.Plugin option_keys must map each callback owner to unique atom keys; " <>
            "got: #{inspect(value)}"
  end
end
