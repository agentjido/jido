defmodule Jido.AgentServer.Plugin do
  @moduledoc """
  Live Agent Server-owned facet of a `Jido.Plugin` package.

  This facet can reject live commands or return one transient package-owned
  runtime input. It cannot replace pure prepared input or change the Agent,
  source Signal, or caller context. It can also prepare outbound Signals,
  declare one permanent runtime root, gate readiness, receive each Turn commit,
  and dispatch owned Directives after commit. Agent Server owns all tasks,
  limits, restart policy, and settlement. The owner wrapper hosts each root
  generation as temporary so it can restart the root with a fresh committed
  state and state version.
  """

  alias Jido.Agent.Command
  alias Jido.AgentServer.Plugin.{Admission, Callbacks, Commit}
  alias Jido.Plugin.{DirectiveContext, Init, SignalContext}

  @doc "Defines an Agent Server-owned Plugin facet."
  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Jido.AgentServer.Plugin

      @doc false
      def __jido_plugin_facet__, do: :agent_server
    end
  end

  @callback admit(runtime_ref :: term() | nil, admission :: Admission.t(), opts :: keyword()) ::
              {:ok, term()} | {:error, term()}
  @callback prepare_dispatch(
              runtime_ref :: term() | nil,
              signal :: Jido.Signal.t(),
              context :: SignalContext.t(),
              opts :: keyword()
            ) :: {:ok, Jido.Signal.t()} | {:error, term()}
  @callback dispatch(
              runtime_ref :: term() | nil,
              directive :: struct(),
              context :: DirectiveContext.t(),
              opts :: keyword()
            ) :: :ok | {:error, term()}
  @callback await_ready(runtime_ref :: term(), opts :: keyword()) :: :ok | {:error, term()}
  @callback validate_options(opts :: keyword()) :: :ok | {:error, term()}

  @doc """
  Receives each successful Turn commit before returned Directives run.

  Notifications run in declaration order, including commits with unchanged
  state or no Directives. Each callback receives its exact committed owned
  value and revision. Return `:ok` or `{:error, reason}`; the callback cannot
  replace state or return Directives. Startup, restore, and direct Agent
  commands do not invoke it.

  Agent Server runs each callback in an owned task. Its timeout is the finite
  `directive_timeout`, or 5,000 milliseconds when that option is `:infinity`.
  A failure skips remaining notifications and Directives and uses the Server
  error policy. The caller has already received the commit result. Neither
  failure nor timeout can undo the commit or completed external work.

  Notifications are not durable or replayed after owner loss. Rebuild a live
  projection from `Jido.Plugin.Init` on startup and runtime replacement.
  """
  @callback after_commit(runtime_ref :: term() | nil, commit :: Commit.t(), opts :: keyword()) ::
              :ok | {:error, term()}

  @optional_callbacks admit: 3,
                      prepare_dispatch: 4,
                      dispatch: 4,
                      await_ready: 2,
                      validate_options: 1,
                      after_commit: 3

  @doc false
  @spec commit_modules([Jido.Plugin.Spec.t()]) :: [module()]
  def commit_modules(specs), do: Callbacks.commit_modules(specs)

  @doc false
  @spec after_commit(Jido.Plugin.Spec.t(), term(), Commit.t()) :: :ok | {:error, term()}
  def after_commit(spec, runtime_ref, commit),
    do: Callbacks.after_commit(spec, runtime_ref, commit)

  @doc false
  @spec admits?([Jido.Plugin.Spec.t()]) :: boolean()
  def admits?(specs), do: Callbacks.admits?(specs)

  @doc false
  @spec admission_modules([Jido.Plugin.Spec.t()]) :: [module()]
  def admission_modules(specs), do: Callbacks.admission_modules(specs)

  @doc false
  @spec dispatch_modules([Jido.Plugin.Spec.t()]) :: [module()]
  def dispatch_modules(specs), do: Callbacks.dispatch_modules(specs)

  @doc false
  @spec admit(Command.t(), [Jido.Plugin.Spec.t()], %{optional(module()) => term() | nil}) ::
          {:ok, Command.t()} | {:error, term()}
  def admit(command, specs, runtime_refs), do: Callbacks.admit(command, specs, runtime_refs)

  @doc false
  @spec admit(
          Command.t(),
          [Jido.Plugin.Spec.t()],
          %{optional(module()) => term() | nil},
          non_neg_integer()
        ) :: {:ok, Command.t()} | {:error, term()}
  def admit(command, specs, runtime_refs, state_version),
    do: Callbacks.admit(command, specs, runtime_refs, state_version)

  @doc false
  @spec prepare_dispatch(
          Jido.Signal.t(),
          [Jido.Plugin.Spec.t()],
          %{optional(module()) => term() | nil},
          SignalContext.t(),
          map()
        ) :: {:ok, Jido.Signal.t()} | {:error, term()}
  def prepare_dispatch(signal, specs, runtime_refs, context, agent_state),
    do: Callbacks.prepare_dispatch(signal, specs, runtime_refs, context, agent_state)

  @doc false
  @spec child_specs(Init.t(), [Jido.Plugin.declaration()] | [Jido.Plugin.Spec.t()]) ::
          {:ok, [Supervisor.child_spec()]} | {:error, term()}
  def child_specs(init, declarations), do: Callbacks.child_specs(init, declarations)

  @doc "Gets one Plugin-owned field from the current complete Agent state."
  @spec state(Init.t(), timeout()) :: {:ok, term()} | {:error, term()}
  def state(%Init{agent_server: agent_server, module: package}, timeout \\ 5_000) do
    Jido.AgentServer.plugin_state(agent_server, package, timeout)
  catch
    :exit, reason -> {:error, {:agent_server_unavailable, reason}}
  end

  @doc false
  @spec dispatch(Jido.Plugin.Spec.t(), term(), struct(), DirectiveContext.t()) ::
          :ok | {:error, term()}
  def dispatch(plugin_spec, runtime_ref, directive, context),
    do: Callbacks.dispatch(plugin_spec, runtime_ref, directive, context)

  @doc false
  @spec await_ready(Jido.Plugin.Spec.t(), term()) :: :ok | {:error, term()}
  def await_ready(plugin_spec, runtime_ref), do: Callbacks.await_ready(plugin_spec, runtime_ref)
end
