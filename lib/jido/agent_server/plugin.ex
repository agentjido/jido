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

  alias Jido.AgentServer.Plugin.{Admission, Commit}
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

  @doc "Gets one Plugin-owned field from the current complete Agent state."
  @spec state(Init.t(), timeout()) :: {:ok, term()} | {:error, term()}
  def state(%Init{agent_server: agent_server, module: package}, timeout \\ 5_000) do
    Jido.AgentServer.plugin_state(agent_server, package, timeout)
  catch
    :exit, reason -> {:error, {:agent_server_unavailable, reason}}
  end
end
