defmodule Jido.AgentServer do
  @moduledoc """
  The public API for one live `Jido.Agent` process.

  `Jido.AgentServer.Runtime` is the private `:gen_statem` callback module. The
  facade does not add a process. `start_link/1` and `start/1` return the Runtime
  PID, and all operations use that PID or its registered name.

  The Server accepts one Signal at a time. It commits the complete Agent state
  before it replies with success. It then runs returned Directives in list
  order. A successful Signal reply confirms the state commit. It does not
  confirm that all post-commit Directives completed.

  Signals that arrive while the Server is busy use OTP event postponement. The
  configured admission limit bounds reached events, but it does not bound the
  complete process mailbox.

  Use `agent/2` for the committed Agent, `snapshot/2` for the Agent and commit
  revision, `status/2` for current work, and `children/2` for live ownership.
  Use `set_debug/3` and `recent_events/3` for a bounded local event history.
  """

  alias Jido.Agent
  alias Jido.AgentServer.{ParentRef, Runtime}
  alias Jido.Signal

  @type server :: pid() | atom() | {:global, term()} | {:via, module(), term()}
  @type signal_result :: {:ok, Agent.t()} | {:error, term()}
  @type call_option :: {:timeout, timeout()} | {:context, map() | keyword() | nil}
  @type upgrade_operation :: (-> :ok | {:error, term()})
  @type state_migration :: (Agent.t() -> {:ok, map()} | {:error, term()})

  @doc """
  Starts one Agent Server linked to the calling process.

  Use `Jido.start_agent/3` for instance-supervised ownership instead.
  """
  @spec start_link(keyword()) :: :gen_statem.start_ret()
  def start_link(opts) when is_list(opts), do: Runtime.start_link(opts)

  @doc false
  def start_link(opts, startup_reply) when is_list(opts),
    do: Runtime.start_link(opts, startup_reply)

  @doc """
  Starts one Agent Server under its Jido instance supervisor.

  The Server links to that supervisor. It does not link to the original caller.
  """
  @spec start(keyword()) :: DynamicSupervisor.on_start_child()
  def start(opts) when is_list(opts), do: Runtime.start(opts)

  @doc "Returns a child specification for one Agent Server."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts), do: Runtime.child_spec(opts)

  @doc """
  Sends one Signal and waits for its commit or failure.

  The third argument accepts a timeout or a keyword list with `:timeout` and
  `:context`. Caller context belongs to this Turn. Jido does not add it to the
  Signal data, committed Agent state, persistence record, or emitted Signals.

  Caller timeout stops waiting. It does not cancel work that already started.
  Use `cancel/2` or `cancel_turn/3` to request cancellation.
  """
  @spec call(server(), Signal.t(), timeout() | [call_option()]) :: signal_result()
  def call(server, signal, timeout_or_opts \\ 5_000),
    do: Runtime.call(server, signal, timeout_or_opts)

  @doc "Sends one asynchronous Signal. Delivery is best effort under overload."
  @spec cast(server(), Signal.t()) :: :ok
  def cast(server, signal), do: Runtime.cast(server, signal)

  @doc "Stops one Agent Server through its normal OTP termination path."
  @spec stop(server(), term(), timeout()) :: :ok
  def stop(server, reason \\ :shutdown, timeout \\ 5_000),
    do: Runtime.stop(server, reason, timeout)

  @doc "Returns one declared Plugin's owned field from the complete Agent state map."
  @spec plugin_state(server(), module(), timeout()) :: {:ok, term()} | {:error, term()}
  def plugin_state(server, plugin, timeout \\ 5_000),
    do: Runtime.plugin_state(server, plugin, timeout)

  @doc "Starts an asynchronous request for one Signal."
  @spec send_request(server(), Signal.t(), timeout()) :: term()
  def send_request(server, signal, timeout \\ 5_000),
    do: Runtime.send_request(server, signal, timeout)

  @doc "Receives the response for `send_request/3`."
  @spec receive_response(term(), timeout()) :: term()
  def receive_response(request_id, timeout \\ 5_000),
    do: Runtime.receive_response(request_id, timeout)

  @doc "Returns the current committed Agent value."
  @spec agent(server(), timeout()) :: Agent.t()
  def agent(server, timeout \\ 5_000), do: Runtime.agent(server, timeout)

  @doc """
  Returns a narrow view of current Agent Server work.

  The result contains the public phase, Agent ID, commit revision, admission
  counts, lifecycle information, and a bounded active-Turn summary.
  """
  @spec status(server(), timeout()) :: map()
  def status(server, timeout \\ 5_000), do: Runtime.status(server, timeout)

  @doc "Waits until Agent runtime children are ready."
  @spec await_ready(server(), timeout()) :: :ok | {:error, term()}
  def await_ready(server, timeout \\ 5_000), do: Runtime.await_ready(server, timeout)

  @doc "Cancels the active executable Turn."
  @spec cancel(server(), timeout()) :: :ok | {:error, term()}
  def cancel(server, timeout \\ 5_000), do: Runtime.cancel(server, timeout)

  @doc "Cancels the active executable Turn only when its stable ID matches."
  @spec cancel_turn(server(), String.t(), timeout()) :: :ok | {:error, term()}
  def cancel_turn(server, turn_id, timeout \\ 5_000),
    do: Runtime.cancel_turn(server, turn_id, timeout)

  @doc "Enables or disables the bounded runtime event buffer for one Agent."
  @spec set_debug(server(), boolean(), timeout()) :: :ok
  def set_debug(server, enabled, timeout \\ 5_000),
    do: Runtime.set_debug(server, enabled, timeout)

  @doc """
  Returns recent Agent runtime events in newest-first order.

  Use `:limit` to request fewer events than the configured maximum. This
  function returns `{:error, :debug_not_enabled}` when the buffer is off.
  """
  @spec recent_events(server(), keyword(), timeout()) :: {:ok, [map()]} | {:error, term()}
  def recent_events(server, opts \\ [], timeout \\ 5_000),
    do: Runtime.recent_events(server, opts, timeout)

  @doc "Returns the PID for an Agent ID in one Registry."
  @spec whereis(module(), String.t(), keyword()) :: pid() | nil
  def whereis(registry, id, opts \\ []), do: Runtime.whereis(registry, id, opts)

  @doc "Returns a Registry via tuple for an Agent ID."
  @spec via_tuple(String.t(), module(), keyword()) :: {:via, Registry, {module(), term()}}
  def via_tuple(id, registry, opts \\ []), do: Runtime.via_tuple(id, registry, opts)

  @doc """
  Returns true when the Agent Server is alive.

  A remote check has a one-second limit. False means that liveness was not
  confirmed. It does not prove that the process stopped during a network fault.
  """
  @spec alive?(server()) :: boolean()
  def alive?(server), do: Runtime.alive?(server)

  @doc "Attaches an owner process and prevents idle hibernation."
  @spec attach(server(), pid(), timeout()) :: :ok | {:error, term()}
  def attach(server, owner_pid \\ self(), timeout \\ 5_000),
    do: Runtime.attach(server, owner_pid, timeout)

  @doc "Detaches an owner process. The idle timer starts after the last detach."
  @spec detach(server(), pid(), timeout()) :: :ok | {:error, term()}
  def detach(server, owner_pid \\ self(), timeout \\ 5_000),
    do: Runtime.detach(server, owner_pid, timeout)

  @doc "Resets the idle timer without attaching an owner process."
  @spec touch(server()) :: :ok
  def touch(server), do: Runtime.touch(server)

  @doc false
  @spec adopt_parent(server(), ParentRef.t()) :: {:ok, map()} | {:error, term()}
  def adopt_parent(server, parent), do: Runtime.adopt_parent(server, parent)

  @doc false
  def creation_info(server), do: Runtime.creation_info(server)

  @doc "Adopts one orphaned Agent as a tracked child."
  @spec adopt_child(server(), pid() | String.t(), term(), map()) :: :ok | {:error, term()}
  def adopt_child(server, child, tag, meta \\ %{}),
    do: Runtime.adopt_child(server, child, tag, meta)

  @doc "Stops one tracked child Agent."
  @spec stop_child(server(), term(), term()) :: :ok | {:error, term()}
  def stop_child(server, tag, reason \\ :normal),
    do: Runtime.stop_child(server, tag, reason)

  @doc "Returns a public view of tracked Agent and Plugin children."
  @spec children(server(), timeout()) :: map()
  def children(server, timeout \\ 5_000), do: Runtime.children(server, timeout)

  @doc """
  Returns the committed Agent and its commit revision as `:state_version`.

  Each successful Turn increases the revision once. A failure before commit
  preserves the state and revision. A Directive failure does not undo a commit.
  """
  @spec snapshot(server(), timeout()) :: map()
  def snapshot(server, timeout \\ 5_000), do: Runtime.snapshot(server, timeout)

  @doc """
  Runs one upgrade operation after the Agent Server becomes idle.

  Signals that arrive after the request stay behind it in OTP event order. The
  operation must return `:ok` or `{:error, reason}`.
  """
  @spec upgrade(server(), upgrade_operation()) :: :ok | {:error, term()}
  def upgrade(server, operation), do: Runtime.upgrade(server, operation)

  @spec upgrade(server(), upgrade_operation(), timeout()) :: :ok | {:error, term()}
  def upgrade(server, operation, timeout) when is_function(operation, 0),
    do: Runtime.upgrade(server, operation, timeout)

  @doc """
  Replaces the live Agent definition with validated migrated state.

  The migration runs after the Server becomes idle. The target must keep the
  same Agent identity and Plugin declarations. A successful change writes the
  required checkpoint before the new Agent becomes visible.
  """
  @spec upgrade(server(), module(), state_migration()) ::
          {:ok, Agent.t()} | {:error, term()}
  def upgrade(server, target_module, migration),
    do: Runtime.upgrade(server, target_module, migration)

  @spec upgrade(server(), module(), state_migration(), timeout()) ::
          {:ok, Agent.t()} | {:error, term()}
  def upgrade(server, target_module, migration, timeout),
    do: Runtime.upgrade(server, target_module, migration, timeout)

  @doc "Persists and stops one Agent Server after it becomes idle."
  @spec hibernate(server(), keyword()) :: :ok | {:error, term()}
  def hibernate(server, opts \\ []), do: Runtime.hibernate(server, opts)
end
