defmodule Jido.AgentServer do
  @moduledoc """
  Runs one serialized Agent Turn at a time.

  Calls, submissions, and casts share one admission and commit boundary.
  Reads remain available while work runs. A caller wait timeout does not
  cancel accepted work. Use `cancel/2` or `cancel_turn/3` to stop a Turn.

  `turn_timeout:` bounds pre-commit work. `exec_opts:` controls owned Runner
  execution. `error_policy:` selects the action after an ordinary Turn
  failure. `status/2` returns a bounded view, and opt-in `history/1` returns
  bounded terminal summaries.

  Activation recovery, Plugin runtime work, composition, durable Agent
  state, durable Flow progress, and post-commit effects use separate
  `Jido.AgentServer.*` owners behind this public API.
  """

  @behaviour :gen_statem

  @typedoc "A local AgentServer PID or registered OTP server name."
  @type server :: :gen_statem.server_ref()

  @typedoc "The result of one accepted Agent Turn."
  @type signal_result :: {:ok, Jido.Agent.instance(), [struct()]} | {:error, term()}

  @typedoc "A unique atom or string that identifies one child relationship."
  @type child_tag :: atom() | String.t()

  @typedoc "One live child worker and its complete activation."
  @type child_info :: %{
          pid: pid(),
          activation: pid(),
          placement: :owned | :independent
        }

  @typedoc "One option for a new child relationship and AgentServer."
  @type child_option ::
          {:placement, :owned | :independent}
          | {:on_parent_exit, :stop | :continue | :emit_orphan}
          | {:orphan_dispatch, Jido.Signal.Dispatch.dispatch_configs()}
          | {:restart, Supervisor.restart()}
          | {:server_options, keyword()}
          | {:meta, map()}

  @typedoc "One option for adopting an existing independent child."
  @type adoption_option ::
          {:placement, :independent}
          | {:on_parent_exit, :stop | :continue | :emit_orphan}
          | {:orphan_dispatch, Jido.Signal.Dispatch.dispatch_configs()}
          | {:restart, Supervisor.restart()}
          | {:meta, map()}

  @typedoc "One committed Agent and revision read in the same server event."
  @type snapshot :: %{agent: Jido.Agent.instance(), state_version: non_neg_integer()}

  @typedoc "One option for a serialized snapshot upgrade."
  @type upgrade_option :: {:context, map()} | {:timeout, timeout()}

  @typedoc "A non-empty stable ID for one open Flow wait."
  @type wait_id :: String.t()

  require Logger

  alias Jido.Agent

  alias Jido.AgentServer.{
    CompositionRuntime,
    Core,
    Durable,
    Effects,
    Plugin,
    RegistrationGuard,
    ReplyGate,
    TopologyRuntime
  }

  alias Jido.AgentServer.Supervisor, as: ServerSupervisor
  alias Jido.Dispatch.Preparation, as: DispatchPreparation
  alias Jido.Agent.Command
  alias Jido.Agent.Runner, as: AgentRunner
  alias Jido.Signal
  alias Jido.Telemetry.Semantic
  alias Jido.Tracing.Context, as: TraceContext
  alias Runic.Runner
  alias Jido.AgentServer.DurableTurn

  defmodule Pending do
    @moduledoc false
    @enforce_keys [:request_id, :owner, :reply_gate]
    @derive {Inspect, only: []}
    defstruct [:request_id, :owner, :reply_gate]
  end

  defmodule Store do
    @moduledoc false
    @behaviour Runic.Runner.Store
    # Durable Flow Turns use the Agent adapter. Ordinary Turns save no graph.
    @impl true
    def init_store(opts), do: {:ok, Keyword.get(opts, :jido)}
    @impl true
    defdelegate save(id, log, state), to: Jido.AgentServer.DurableTurn.CheckpointStore
    @impl true
    defdelegate load(id, state), to: Jido.AgentServer.DurableTurn.CheckpointStore
    @impl true
    def list(_state), do: {:ok, []}
    @impl true
    def exists?(_id, _state), do: false
  end

  @typedoc "An owner-bound handle for one submitted Turn result."
  @opaque pending :: %Pending{
            request_id: :gen_statem.request_id(),
            owner: pid(),
            reply_gate: pid()
          }

  @doc "Returns a child specification for OTP supervision."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    agent = Keyword.fetch!(opts, :agent)

    %{
      id: {__MODULE__, opts[:jido], opts[:partition], agent.id},
      start: ServerSupervisor.start_spec(opts),
      restart: :transient,
      type: :supervisor,
      shutdown: :infinity
    }
  end

  @doc "Starts a registered AgentServer under the selected Jido instance supervisor."
  @spec start(keyword()) :: Supervisor.on_start_child()
  def start(opts) when is_list(opts) do
    if Keyword.keyword?(opts) and not is_nil(opts[:jido]) do
      with {:ok, opts} <- runtime_options(opts),
           :ok <- validate_options(opts),
           {:ok, _agent} <- Jido.Agent.Validation.validate_instance(opts[:agent]) do
        case ServerSupervisor.start_activation(
               Jido.agent_supervisor_name(opts[:jido]),
               child_spec(opts)
             ) do
          {:error, {:shutdown, {:failed_to_start_child, __MODULE__, {:already_started, pid}}}} ->
            {:error, {:already_started, pid}}

          result ->
            result
        end
      end
    else
      invalid_options("start requires a Jido instance")
    end
  catch
    :exit, _ -> invalid_options("Jido instance is not available")
  end

  def start(_), do: invalid_options("options must be a keyword list")

  @doc "Looks up an AgentServer in one instance and partition. Returns nil when absent."
  @spec whereis(atom(), String.t(), keyword()) :: pid() | nil
  def whereis(jido, id, opts \\ []) do
    with true <- is_atom(jido) and not is_nil(jido) and is_binary(id),
         true <- Core.unique_keyword?(opts) and Keyword.keys(opts) -- [:partition] == [],
         true <- valid_partition?(opts[:partition]),
         [{pid, :ready}] <-
           Registry.lookup(
             Jido.registry_name(jido),
             RegistrationGuard.registry_key(id, opts[:partition])
           ),
         true <- alive?(pid) do
      pid
    else
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc "Returns true for a live local AgentServer PID or OTP name."
  @spec alive?(server()) :: boolean()
  def alive?(server) do
    case GenServer.whereis(server) do
      pid when is_pid(pid) and node(pid) == node() ->
        Process.alive?(pid) and :proc_lib.translate_initial_call(pid) == {__MODULE__, :init, 1}

      _ ->
        false
    end
  rescue
    _ -> false
  catch
    :exit, _ -> false
  end

  @doc """
  Starts a bare worker with one validated Agent instance and a running `runner:`.
  Runtime Plugins require an activation. Prefer `child_spec/1` or `start/1`.
  Bare-worker standalone use requires the nested Store module. `jido:` selects the live
  instance's Runner, Store, and registration. Turns are local and temporary.
  `max_postponed_signals:` defaults to 1,000; use a non-negative integer or
  `:infinity`. This bounds postponed turns, not the process mailbox.
  `turn_timeout:` defaults to 60,000 ms; use any non-negative integer in
  milliseconds or `:infinity`. Long Turn deadlines use bounded timer intervals.
  """
  @spec start_link(keyword()) :: :gen_statem.start_ret()
  def start_link(opts) when is_list(opts) do
    with {:ok, opts} <- activation_options(opts),
         {:ok, specs} <-
           Jido.Plugin.Normalizer.normalize_all(Jido.Agent.runtime_plugins(opts[:agent])) do
      if not Jido.Agent.Topology.empty?(opts[:agent].topology) or
           TopologyRuntime.buses(opts[:agent]) != [] or
           opts[:persistence] not in [nil, false] or
           Enum.any?(specs, &match?(%{agent_server: %{runtime?: true}}, &1)) do
        invalid_options("runtime Plugins require a supervisor; use child_spec/1 or start/1")
      else
        start_worker(opts, nil)
      end
    end
  end

  def start_link(_opts), do: invalid_options("options must be a keyword list")

  @doc false
  def activation_options(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      with {:ok, opts} <- runtime_options(opts),
           :ok <- validate_options(opts),
           {:ok, agent} <- Jido.Agent.Validation.validate_instance(Keyword.fetch!(opts, :agent)),
           :ok <- Agent.validate_runtime_support(agent),
           do: {:ok, Keyword.put(opts, :agent, agent)}
    else
      invalid_options("options must be a keyword list")
    end
  end

  def activation_options(_), do: invalid_options("options must be a keyword list")

  @doc false
  def start_worker(opts, activation) do
    initial = {Keyword.fetch!(opts, :agent), Keyword.put(opts, :activation, activation)}

    case Keyword.get(opts, :name) do
      nil -> :gen_statem.start_link(__MODULE__, initial, [])
      name when is_atom(name) -> :gen_statem.start_link({:local, name}, __MODULE__, initial, [])
      name -> :gen_statem.start_link(name, __MODULE__, initial, [])
    end
  end

  defp normalize_stop_reason(reason) when reason in [:normal, :shutdown], do: reason
  defp normalize_stop_reason({:shutdown, _} = reason), do: reason
  defp normalize_stop_reason(reason), do: {:shutdown, reason}

  defp runtime_options(opts) do
    with true <- Core.unique_keyword?(opts),
         {:ok, opts} <- instance_options(opts),
         {:ok, opts} <- Core.with_turn_timeout(opts) do
      {:ok, Keyword.merge(Core.runtime_defaults(), opts)}
    else
      false -> invalid_options("startup option keys must be unique")
      error -> error
    end
  end

  defp instance_options(opts) do
    case Keyword.get(opts, :jido) do
      nil ->
        if is_nil(opts[:partition]),
          do: {:ok, opts},
          else: invalid_options("partition requires a Jido instance")

      jido when is_atom(jido) ->
        with pid when is_pid(pid) <- Process.whereis(jido),
             {:supervisor, Jido, 1} <- :proc_lib.translate_initial_call(pid),
             true <- instance_children_live?(pid, jido),
             runner = Jido.exec_runner_name(jido),
             true <- Keyword.get(opts, :runner, runner) == runner,
             true <- valid_partition?(opts[:partition]) do
          {:ok,
           Jido.instance_agent_server_options(jido)
           |> Keyword.merge(opts)
           |> Keyword.put(:runner, runner)}
        else
          _ -> invalid_options("invalid Jido instance, partition, or Runner ownership")
        end

      _ ->
        invalid_options("jido must name a running instance")
    end
  end

  defp instance_children_live?(pid, jido) do
    children = Supervisor.which_children(pid)

    Enum.all?(
      [
        Jido.registry_name(jido),
        Jido.agent_supervisor_name(jido),
        Jido.registration_guard_name(jido)
      ],
      fn name ->
        child = Process.whereis(name)
        is_pid(child) and Enum.any?(children, fn {_, pid, _, _} -> pid == child end)
      end
    )
  end

  defp valid_partition?(nil), do: true
  defp valid_partition?(value), do: is_binary(value) and byte_size(value) > 0

  defp valid_name?(nil), do: true
  defp valid_name?(name) when is_atom(name), do: true
  defp valid_name?({:global, _}), do: true

  defp valid_name?({:via, module, _}) when is_atom(module) and not is_nil(module),
    do: Code.ensure_loaded?(module) and function_exported?(module, :register_name, 2)

  defp valid_name?(_), do: false

  @doc false
  def validate_defaults(opts) do
    if Core.unique_keyword?(opts) and Keyword.keys(opts) -- Core.runtime_keys() == [] do
      validate_runtime(Keyword.merge(Core.runtime_defaults(), opts))
    else
      invalid_options("invalid instance AgentServer defaults")
    end
  end

  defp validate_options(opts) do
    name = Keyword.get(opts, :name)

    cond do
      Keyword.keys(opts) -- Core.startup_keys() != [] ->
        invalid_options("unknown startup options")

      not Keyword.has_key?(opts, :agent) ->
        invalid_options("expected :agent option")

      not valid_name?(name) ->
        invalid_options("invalid OTP name")

      not is_atom(Keyword.get(opts, :runner)) or is_nil(Keyword.get(opts, :runner)) ->
        invalid_options("expected a named Runic Runner in :runner")

      is_nil(Process.whereis(Keyword.fetch!(opts, :runner))) ->
        invalid_options("Runner is not running")

      true ->
        with :ok <- validate_runner(Keyword.fetch!(opts, :runner), opts[:jido]),
             do: validate_runtime(opts)
    end
  end

  defp validate_runtime(opts) do
    with :ok <- Core.validate_runtime(opts),
         :ok <- Core.validate_timeout(opts, :directive_timeout),
         :ok <- Core.validate_timeout(opts, :readiness_timeout),
         :ok <- Core.validate_timeout(opts, :commit_timeout),
         :ok <- Durable.validate_runtime(opts),
         :ok <- Core.validate_timeout(opts, :idle_timeout, false),
         :ok <- Core.validate_setting(opts[:idle_policy] in [:stop, :hibernate], :idle_policy),
         :ok <- Core.validate_limit(opts, :max_directives_per_turn),
         :ok <-
           Core.validate_setting(
             is_nil(opts[:directive_handler]) or is_function(opts[:directive_handler], 2),
             :directive_handler
           ),
         :ok <-
           Core.validate_setting(
             Effects.validate_dispatch(opts[:default_dispatch]) == :ok,
             :default_dispatch
           ),
         do: :ok
  end

  defp validate_runner(runner, _jido) do
    with pid when is_pid(pid) <- Process.whereis(runner),
         {:supervisor, Runner, 1} <- :proc_lib.translate_initial_call(pid),
         true <- live_runner_children?(runner, pid),
         {store, _state} <- Runner.get_store(runner),
         true <-
           store == Store do
      :ok
    else
      _other -> invalid_options("Runner must be running with Jido.AgentServer.Store")
    end
  rescue
    ArgumentError -> invalid_options("Runner configuration is unavailable")
  catch
    :exit, _reason -> invalid_options("Runner is not available")
  end

  defp live_runner_children?(runner, pid) do
    children = Supervisor.which_children(pid)

    Enum.all?([Registry, TaskSupervisor, WorkerSupervisor], fn suffix ->
      name = Module.concat(runner, suffix)

      Enum.any?(children, fn
        {^name, child, :supervisor, _modules} when is_pid(child) ->
          Process.whereis(name) == child

        _child ->
          false
      end)
    end)
  end

  defp invalid_options(message), do: Core.invalid_options(message)

  @doc "Stops the server and its active turn through OTP termination."
  @spec stop(server(), term(), timeout()) :: :ok | {:error, term()}
  def stop(server, reason \\ :shutdown, timeout \\ 5_000) do
    deadline =
      if timeout == :infinity, do: :infinity, else: System.monotonic_time(:millisecond) + timeout

    reason =
      case reason do
        :normal -> :normal
        :shutdown -> :shutdown
        {:shutdown, _} -> reason
        other -> {:shutdown, other}
      end

    case :gen_statem.call(server, :stop_target, remaining_wait(deadline)) do
      {:error, _} = error ->
        error

      nil ->
        :gen_statem.stop(server, reason, remaining_wait(deadline))

      root ->
        ref = Process.monitor(root)

        try do
          :gen_statem.stop(server, reason, remaining_wait(deadline))
          await_activation_down(root, ref, deadline, {:stop, [server, reason, timeout]})
          :ok
        after
          Process.demonitor(ref, [:flush])
        end
    end
  end

  defp await_activation_down(root, ref, deadline, {operation, args}) do
    receive do
      {:DOWN, ^ref, :process, ^root, _} -> :ok
    after
      remaining_wait(deadline) -> exit({:timeout, {__MODULE__, operation, args}})
    end
  end

  defp remaining_wait(:infinity), do: :infinity
  defp remaining_wait(deadline), do: max(0, deadline - System.monotonic_time(:millisecond))

  @doc """
  Cancels the active turn and waits for owned work to stop. Returns `:ok` when
  cleanup is confirmed, or `{:error, :not_running}` when idle. The turn caller
  receives `{:error, :cancelled}`. Caller wait timeout exits the caller, as with
  OTP calls; it does not undo cancellation.
  Calls from owned work return `{:error, :reentrant_turn}`.
  """
  @spec cancel(server(), timeout()) :: :ok | {:error, term()}
  def cancel(server, timeout \\ 5_000), do: cancel_request(server, :active, timeout)

  @doc """
  Cancels only the active turn with this ID. A different active ID returns
  `{:error, :stale_turn}`. An idle server returns `{:error, :not_running}`.
  Successful cancellation confirms cleanup, as with `cancel/2`.
  """
  @spec cancel_turn(server(), String.t(), timeout()) :: :ok | {:error, term()}
  def cancel_turn(server, turn_id, timeout \\ 5_000) when is_binary(turn_id),
    do: cancel_request(server, turn_id, timeout)

  defp cancel_request(server, id, timeout) do
    with :ok <- Core.validate_wait(timeout), do: :gen_statem.call(server, {:cancel, id}, timeout)
  end

  @doc """
  Closes admission and rejects queued turns with `:quiesced`. Waits for the
  active turn and post-commit work. Set `active: :cancel` to cancel pre-commit
  work; accepted saves and effects must finish. Reads remain available.
  `timeout:` is a finite control budget (default 5,000 ms). On expiry admission
  stays closed. Caller wait allows a further 1,000 ms for the control reply;
  an unresponsive server causes an OTP timeout exit. Call `resume/2` after the
  server settles. Owned callbacks cannot
  call this synchronous control.
  """
  @spec quiesce(server(), keyword()) :: :ok | {:error, term()}
  def quiesce(server, opts \\ []), do: control_request(server, :quiesce, opts)

  @doc "Opens admission after quiescence. An uncertain hibernation save forbids resume."
  @spec resume(server(), timeout()) :: :ok | {:error, term()}
  def resume(server, timeout \\ 5_000) do
    with :ok <- Core.validate_wait(timeout), do: :gen_statem.call(server, :resume, timeout)
  end

  @doc """
  Saves the settled Agent at its current revision, then stops the activation.
  Requires configured persistence. Success confirms activation exit. Accepts the
  same options as `quiesce/2`; cleanup has a further `timeout:` wait budget.
  Failure returns `{:error, %{reason: reason, resumable?: boolean}}`. A known
  no-write failure restores prior admission. Conflict or uncertainty keeps the
  live Agent closed and forbids resume. Required turn writes still follow their
  separate fail-stop contract.
  """
  @spec hibernate(server(), keyword()) :: :ok | {:error, term()}
  def hibernate(server, opts \\ []) do
    with {:ok, _active, _timeout} <- Core.control_options(opts),
         target when is_pid(target) <- :gen_statem.call(server, :stop_target) do
      ref = Process.monitor(target)

      try do
        case control_request(server, :hibernate, opts) do
          :saved ->
            deadline = System.monotonic_time(:millisecond) + Keyword.get(opts, :timeout, 5_000)
            await_activation_down(target, ref, deadline, {:hibernate, [server, opts]})

          result ->
            result
        end
      after
        Process.demonitor(ref, [:flush])
      end
    else
      nil -> Durable.error(:activation_required, true)
      error -> error
    end
  end

  defp control_request(server, kind, opts) do
    with {:ok, active, timeout} <- Core.control_options(opts) do
      # Allow the server to report its control deadline. The caller still has
      # a finite OTP wait if delivery or the server itself cannot progress.
      wait = Core.control_wait(timeout)

      :gen_statem.call(
        server,
        {:control, kind, active, timeout},
        wait
      )
    end
  end

  @doc "Attaches one owner. Repeated attachment is idempotent and prevents idle expiry."
  @spec attach(server(), pid(), timeout()) :: :ok | {:error, term()}
  def attach(server, owner \\ self(), timeout \\ 5_000),
    do: owner_request(server, :attach, owner, timeout)

  @doc "Detaches one owner. The last detach starts a new idle budget."
  @spec detach(server(), pid(), timeout()) :: :ok | {:error, term()}
  def detach(server, owner \\ self(), timeout \\ 5_000),
    do: owner_request(server, :detach, owner, timeout)

  defp owner_request(server, kind, owner, timeout) do
    with :ok <- Core.validate_setting(is_pid(owner), :owner),
         :ok <- Core.validate_wait(timeout),
         do: :gen_statem.call(server, {kind, owner}, timeout)
  end

  @doc "Restarts the idle budget. Does not open closed admission."
  @spec touch(server()) :: :ok
  def touch(server), do: :gen_statem.call(server, :touch)

  @doc "Returns the saved Agent instance."
  @spec agent(server(), timeout()) :: Agent.instance() | {:error, term()}
  def agent(server, timeout \\ 5_000) do
    with :ok <- Core.validate_wait(timeout), do: :gen_statem.call(server, :agent, timeout)
  end

  @doc "Returns one committed Plugin-owned state field."
  @spec plugin_state(server(), module(), timeout()) :: {:ok, term()} | {:error, term()}
  def plugin_state(server, plugin, timeout \\ 5_000) do
    with :ok <- Core.validate_wait(timeout),
         do: :gen_statem.call(server, {:plugin_state, plugin}, timeout)
  end

  @doc """
  Runs one Signal. Accepts a timeout or `timeout:`, `admission_timeout:`, and
  `context:` options. Admission timeout defaults to 5,000 ms; use `:infinity`
  to let queued work wait without a deadline. It is separate from caller wait.
  Finite admission deadlines require a caller on the server's node.
  Caller timeout exits the caller, as with OTP calls; it does not cancel work.
  Finite waits must be in `0..4_294_967_295` ms. Context accepts a
  map, keyword list, or nil. It is not stored in Agent state or Signal data.
  `:turn_id` and the Agent command context keys are reserved.
  """
  @spec call(server(), Signal.t(), timeout() | keyword()) :: signal_result()
  def call(server, signal, timeout_or_opts \\ 5_000) do
    opts = if is_list(timeout_or_opts), do: timeout_or_opts, else: [timeout: timeout_or_opts]

    with {:ok, signal} <- Command.normalize_signal(signal),
         {:ok, context} <- Core.turn_context(opts, [:timeout, :admission_timeout, :context]),
         timeout = Keyword.get(opts, :timeout, 5_000),
         :ok <- Core.validate_wait(timeout),
         {:ok, deadline} <- Core.admission_deadline(opts) do
      reply_gate = ReplyGate.start(self(), server)

      try do
        result =
          :gen_statem.call(server, turn_event(signal, context, deadline, reply_gate), timeout)

        :ok = ReplyGate.open(reply_gate)
        result
      catch
        kind, reason ->
          ReplyGate.abandon(reply_gate)
          :erlang.raise(kind, reason, __STACKTRACE__)
      end
    end
  end

  @doc """
  Submits one turn with optional `context:` and `admission_timeout:` and returns
  a pending result handle. Admission timeout defaults to 5,000 ms. It limits
  the wait before execution, not execution itself or a later `await` call.
  Finite admission deadlines require a caller on the server's node.

  Submission does not confirm that execution has started. Use `await/2` from
  this same process to collect the result. The handle hides the OTP request.
  Invalid options return an error before submission.
  """
  @spec submit(server(), Signal.t(), keyword()) :: pending() | {:error, term()}
  def submit(server, signal, opts \\ []) do
    with {:ok, signal} <- Command.normalize_signal(signal),
         {:ok, context} <- Core.turn_context(opts, [:context, :admission_timeout]),
         {:ok, deadline} <- Core.admission_deadline(opts) do
      reply_gate = ReplyGate.start(self(), server)

      %Pending{
        request_id:
          :gen_statem.send_request(server, turn_event(signal, context, deadline, reply_gate)),
        owner: self(),
        reply_gate: reply_gate
      }
    end
  end

  @doc """
  Sends one Signal without a reply, with optional `context:`.
  Delivery is best effort. A failed turn logs its ID and preserves state.
  Excess casts are dropped and logged when the postponed turn limit is reached.
  Casts have no admission deadline. Invalid options fail before sending.
  """
  @spec cast(server(), Signal.t(), keyword()) :: :ok | {:error, term()}
  def cast(server, signal, opts \\ []) do
    with {:ok, signal} <- Command.normalize_signal(signal),
         {:ok, context} <- Core.turn_context(opts, [:context]) do
      :gen_statem.cast(server, turn_event(signal, context, :infinity, nil))
    end
  end

  defp turn_event(signal, context, deadline, reply_gate),
    do: {:turn, make_ref(), signal, context, deadline, reply_gate}

  @doc """
  Waits for a submitted turn and returns the same turn result as `call/3`.

  A timeout returns `{:error, :timeout}` without cancelling the turn or losing
  its reply. Call `await` again from the submitting process to keep waiting.
  A result can be collected only once. This handle is not durable and cannot
  be transferred to another process. Use `abandon/1` when its reply is no longer
  needed. Do not await a handle after collection or abandonment.
  """
  @spec await(pending(), timeout()) :: signal_result()
  def await(pending, timeout \\ 5_000)

  def await(%Pending{owner: owner, request_id: request_id, reply_gate: reply_gate}, timeout)
      when owner == self() do
    with :ok <- Core.validate_wait(timeout) do
      case :gen_statem.wait_response(request_id, timeout) do
        {:reply, result} ->
          ReplyGate.open(reply_gate)
          result

        :timeout ->
          {:error, :timeout}

        {:error, {reason, _server}} ->
          ReplyGate.abandon(reply_gate)

          {:error,
           Jido.Error.execution_error("Agent server stopped before the turn replied", %{
             reason: reason
           })}
      end
    end
  end

  def await(%Pending{}, _timeout),
    do: invalid_options("await must run in the process that submitted the turn")

  @doc """
  Discards a pending reply and releases its OTP request monitor. This does not
  cancel the submitted turn. Only the submitting process can abandon a handle.
  Discards an already queued reply too. Do not await this handle again.
  """
  @spec abandon(pending()) :: :ok | {:error, term()}
  def abandon(%Pending{owner: owner, request_id: request_id, reply_gate: reply_gate})
      when owner == self() do
    ReplyGate.abandon(reply_gate)
    _response = :gen_statem.receive_response(request_id, 0)
    :ok
  end

  def abandon(%Pending{}),
    do: invalid_options("abandon must run in the process that submitted the turn")

  @doc "Returns phase, identity, revision, queue counts, and a bounded active turn view."
  @spec status(server(), timeout()) :: map() | {:error, term()}
  def status(server, timeout \\ 5_000) do
    with :ok <- Core.validate_wait(timeout), do: :gen_statem.call(server, :status, timeout)
  end

  @doc """
  Saves a Signal as input to an open durable Flow wait. This is not a new Turn.

  Use the non-empty wait ID from `status/2`. Signal `id` identifies a retry,
  `type` selects the event, and `data` must be a portable plain Map payload.
  `:ok` confirms saved acceptance, not completion. A caller timeout does not
  cancel delivery. Retry the same Signal and wait ID. Delivery is available
  only while the Worker is suspended.
  """
  @spec deliver_wait(server(), wait_id(), Signal.t(), timeout()) ::
          :ok | {:error, term()}
  def deliver_wait(server, wait_id, signal, timeout \\ 5_000)

  def deliver_wait(server, wait_id, %Signal{} = signal, timeout) do
    with :ok <- validate_wait_id(wait_id),
         :ok <- Core.validate_wait(timeout) do
      input = %{id: signal.id, event: signal.type, payload: signal.data, wait_id: wait_id}
      :gen_statem.call(server, {:wait_input, input}, timeout)
    end
  end

  def deliver_wait(_server, _wait_id, _signal, _timeout),
    do: invalid_options("wait input must be a Signal")

  defp validate_wait_id(wait_id) when is_binary(wait_id) and byte_size(wait_id) > 0, do: :ok
  defp validate_wait_id(_wait_id), do: invalid_options("wait ID must be a non-empty string")

  @doc "Waits for Plugin startup and readiness. Caller timeout does not stop startup."
  @spec await_ready(server(), timeout()) :: :ok | {:error, term()}
  def await_ready(server, timeout \\ 5_000) do
    with :ok <- Core.validate_wait(timeout), do: :gen_statem.call(server, :await_ready, timeout)
  end

  @doc "Returns terminal summaries in chronological order when debug is enabled."
  @spec history(server()) :: [map()]
  def history(server), do: :gen_statem.call(server, :history)

  @impl true
  def callback_mode, do: :handle_event_function

  @impl true
  def init({agent, opts}) do
    Process.flag(:trap_exit, true)
    Process.set_label({__MODULE__, agent.id})
    runner = Keyword.fetch!(opts, :runner)

    case register_instance(agent.id, opts) do
      {:ok, monitors} -> init_registered(agent, runner, opts, monitors)
      {:error, reason} -> {:stop, reason}
    end
  end

  defp register_instance(id, opts) do
    case opts[:jido] do
      nil ->
        {:ok, %{}}

      jido ->
        registry = Jido.registry_name(jido)
        key = RegistrationGuard.registry_key(id, opts[:partition])

        with :ok <- RegistrationGuard.claim(jido, key, self(), opts[:activation]),
             :ok <- register_ready(registry, key) do
          {:ok,
           Map.new(
             [jido, registry, Jido.registration_guard_name(jido)],
             fn name -> {Process.monitor(Process.whereis(name)), name} end
           )}
        end
    end
  catch
    :exit, _ -> {:error, :instance_unavailable}
  end

  defp register_ready(registry, key) do
    case Registry.register(registry, key, :starting) do
      {:ok, _} ->
        :ok

      {:error, {:already_registered, pid}} when pid == self() ->
        Registry.update_value(registry, key, fn _ -> :starting end)
        :ok

      error ->
        error
    end
  end

  defp init_registered(agent, runner, opts, monitors) do
    Semantic.point([:jido, :agent_server, :lifecycle, :start], %{agent_id: agent.id})

    {:ok, specs} = Jido.Plugin.Normalizer.normalize_all(Jido.Agent.runtime_plugins(agent))

    data =
      Map.merge(Map.new(Core.runtime_keys(), &{&1, Keyword.fetch!(opts, &1)}), %{
        agent: agent,
        runner: runner,
        jido: opts[:jido],
        partition: opts[:partition],
        instance_monitors: monitors,
        plugin_specs: specs,
        plugin_refs: %{},
        activation: opts[:activation],
        activation_state: opts[:activation_state],
        generation: make_ref(),
        parent: monitor_parent(opts[:activation_state]),
        parent_effect: nil,
        child_monitors: monitor_children(opts[:activation_state]),
        bootstrap: nil,
        ready_waiters: [],
        last_effect_outcome: nil,
        runner_ref: Process.monitor(Process.whereis(runner)),
        state_version: Keyword.get(opts, :state_version, 0),
        active: nil,
        server_turn: nil,
        postponed: MapSet.new(),
        queued_from: %{},
        admission_mode: runtime_value(opts[:activation_state], :admission, :open),
        control: nil,
        owners: monitor_owners(opts[:activation_state]),
        idle_timer: nil,
        error_count: 0,
        last_outcome: nil,
        history: :queue.new()
      })

    if data.persistence not in [nil, false] do
      mode = Durable.persistence_mode(data.activation_state, data.persistence_mode)
      bootstrap(data, :persistence, data.persistence_timeout, fn -> Durable.start(data, mode) end)
    else
      initialize_plugins(data)
    end
  end

  defp initialize_plugins(data) do
    case Jido.Agent.Composition.bind(data.agent) do
      {:ok, agent} ->
        {:ok, specs} = Jido.Plugin.Normalizer.normalize_all(Jido.Agent.runtime_plugins(agent))

        if data.activation_state,
          do: Durable.restore(data.activation_state, agent, data.state_version)

        initialize_bound_plugins(%{data | agent: agent, plugin_specs: specs})

      {:error, reason} ->
        {:stop, reason}
    end
  end

  defp initialize_bound_plugins(data) do
    if not Jido.Agent.Topology.empty?(data.agent.topology) or
         TopologyRuntime.buses(data.agent) != [] or
         ServerSupervisor.execution(data.activation_state) != nil or
         Enum.any?(data.plugin_specs, &match?(%{agent_server: %{runtime?: true}}, &1)) do
      owner = self()

      bootstrap(data, :plugins, data.readiness_timeout, fn ->
        runtime = Map.put(data, :owner, owner)

        with :ok <- ServerSupervisor.close_execution(data.activation_state),
             :ok <- CompositionRuntime.validate_runtime(runtime),
             {:ok, refs} <- Plugin.bootstrap(data, owner),
             {:ok, _} <- CompositionRuntime.reconcile(runtime),
             do: {:ok, refs}
      end)
    else
      mark_ready(data)
      replies = Enum.flat_map(data.ready_waiters, &reply(&1, :ok))

      {:ok, :idle, arm_idle(%{data | bootstrap: nil, ready_waiters: []}),
       replies ++
         [{:next_event, :internal, :recover_turn}, {:next_event, :internal, :control_progress}]}
    end
  end

  defp bootstrap(data, kind, timeout, fun) do
    token = make_ref()
    deadline = System.monotonic_time(:millisecond) + timeout
    timer = Process.send_after(self(), {:readiness_timeout, token}, timeout)
    task = Task.async(fun)
    boot = %{task: task, token: token, timer: timer, deadline: deadline, kind: kind}
    phase = if kind == :persistence, do: :restoring, else: :initializing
    {:ok, phase, %{data | bootstrap: boot}}
  end

  defp mark_ready(%{jido: nil}), do: :ok

  defp mark_ready(data) do
    Registry.update_value(
      Jido.registry_name(data.jido),
      RegistrationGuard.registry_key(data.agent.id, data.partition),
      fn _ -> :ready end
    )

    :ok
  end

  @doc """
  Starts a tagged local child Agent. The default `placement: :owned` puts its
  activation under the parent. `:independent` uses the instance supervisor.
  Independent children accept `on_parent_exit: :stop | :continue | :emit_orphan`.
  The last policy requires `orphan_dispatch:`. `restart:` defaults to
  `:transient`. `server_options:` can set AgentServer runtime options, but
  cannot replace the Agent identity, OTP name, instance, partition, or Runner.
  `meta:` must be a plain Map and is returned in the child's parent status.
  Parent means activation lifetime, not one server PID. A caller timeout does
  not cancel supervised startup.
  """
  @spec spawn_child(server(), Agent.instance(), child_tag(), [child_option()]) ::
          {:ok, pid()} | {:error, term()}
  def spawn_child(server, agent, tag, opts \\ [])

  def spawn_child(server, %Agent{} = agent, tag, opts) do
    CompositionRuntime.spawn_child(server, agent, tag, opts)
  end

  def spawn_child(_server, _agent, _tag, _opts),
    do: invalid_options("expected a complete child Agent instance")

  @doc "Returns one committed Agent and revision from the same server event."
  @spec snapshot(server(), timeout()) :: snapshot() | {:error, term()}
  def snapshot(server, timeout \\ 5_000) do
    with :ok <- Core.validate_wait(timeout), do: :gen_statem.call(server, :snapshot, timeout)
  end

  @doc """
  Runs a snapshot upgrade Action through the serial commit boundary.

  Options can be a unique keyword list or plain Map. They are `context:` with
  a plain Map and `timeout:` with a valid wait timeout. A successful upgrade
  returns the accepted Agent with no Directives.
  """
  @spec upgrade(server(), term(), map() | [upgrade_option()]) ::
          {:ok, Agent.instance(), []} | {:error, term()}
  def upgrade(server, action, opts \\ []) do
    with {:ok, options} <- Jido.Agent.Validation.options(opts, [:context, :timeout]),
         context = Map.get(options, :context, %{}),
         :ok <- Jido.Agent.Data.plain_map(context),
         timeout = Map.get(options, :timeout, 5_000),
         :ok <- Core.validate_wait(timeout) do
      :gen_statem.call(server, {:upgrade, make_ref(), action, context}, timeout)
    end
  end

  @doc "Returns live tagged children with separate worker and activation PIDs."
  @spec children(server(), timeout()) ::
          %{optional(child_tag()) => child_info()} | {:error, term()}
  def children(server, timeout \\ 5_000) do
    with :ok <- Core.validate_wait(timeout) do
      context = :gen_statem.call(server, :child_context, timeout)
      CompositionRuntime.children(context)
    end
  end

  @doc "Returns live topology members in slot order. Await readiness before use."
  @spec members(server(), atom(), timeout()) :: [pid()] | {:error, term()}
  def members(server, name, timeout \\ 5_000) do
    with :ok <- Core.validate_wait(timeout),
         do: :gen_statem.call(server, {:topology_members, name}, timeout)
  end

  @doc """
  Stops the complete tagged child activation and confirms its shutdown.
  Removing a permanent entry uses OTP supervisor shutdown.
  """
  @spec stop_child(server(), child_tag(), term()) :: :ok | {:error, term()}
  def stop_child(server, tag, reason \\ :shutdown) do
    CompositionRuntime.stop_child(server, tag, reason)
  end

  @doc """
  Attaches an independent orphan to a new logical parent in the same instance
  and partition. Rejects bare workers, unavailable ancestry, and adoption while
  an orphan notification is pending. Accepts relationship options only; it does
  not reconfigure the existing child AgentServer.
  """
  @spec adopt_child(server(), server(), child_tag(), [adoption_option()]) ::
          :ok | {:error, term()}
  def adopt_child(server, child, tag, opts \\ []) do
    CompositionRuntime.adopt_child(server, child, tag, opts)
  end

  @doc "Returns the activation supervisor PID, or nil for a bare worker."
  @spec activation(server()) :: pid() | nil
  def activation(server), do: :gen_statem.call(server, :activation)

  @doc "Returns the live request worker for an activation root, or nil when unavailable."
  @spec worker(pid()) :: pid() | nil
  def worker(activation), do: ServerSupervisor.live_worker(activation)

  defp public_parent(nil), do: nil
  defp public_parent(parent), do: Map.drop(parent, [:monitor, :state, :token, :dispatch])

  defp monitor_parent(nil), do: nil

  defp monitor_parent(state) do
    case ServerSupervisor.parent(state) do
      nil -> nil
      parent -> Map.put(parent, :monitor, Process.monitor(parent.activation))
    end
  end

  defp forget_child_monitors(monitors, tag, token) do
    Enum.reduce(monitors, %{}, fn {ref, value}, acc ->
      case value do
        {_, ^tag, ^token} ->
          Process.demonitor(ref, [:flush])
          acc

        _ ->
          Map.put(acc, ref, value)
      end
    end)
  end

  defp monitor_children(nil), do: %{}

  defp monitor_children(state) do
    Map.new(
      Enum.map(ServerSupervisor.records(state), fn {{:child, tag}, record} ->
        {kind, pid} =
          case record do
            %{root: root} -> {:root, root}
            %{caller: caller} -> {:reservation, caller}
          end

        {Process.monitor(pid), {kind, tag, record.token}}
      end)
    )
  end

  @impl true
  def handle_event({:call, from}, :child_context, _phase, data) do
    context = %{
      activation: data.activation,
      state: data.activation_state,
      agent_id: data.agent.id,
      jido: data.jido,
      partition: data.partition,
      opts:
        Enum.map(Core.runtime_keys(), &{&1, Map.fetch!(data, &1)}) ++
          [runner: data.runner, jido: data.jido, partition: data.partition]
    }

    {:keep_state_and_data, reply(from, context)}
  end

  def handle_event({:call, from}, {:topology_members, name}, _phase, data) do
    {:keep_state_and_data, reply(from, TopologyRuntime.members(data.activation_state, name))}
  end

  def handle_event({:call, from}, {:reserve_child, tag, token}, _phase, data) do
    {caller, _} = from
    result = ServerSupervisor.reserve(data.activation_state, tag, token, caller)

    data =
      if result == :ok,
        do: %{
          data
          | child_monitors:
              Map.put(data.child_monitors, Process.monitor(caller), {:reservation, tag, token})
        },
        else: data

    {:keep_state, data, reply(from, result)}
  end

  def handle_event({:call, from}, {:forget_child, tag, root}, _phase, data) do
    case :ets.lookup(data.activation_state, {:child, tag}) do
      [{_, %{root: ^root, token: token}}] ->
        ServerSupervisor.release(data.activation_state, tag, token)

      _ ->
        :ok
    end

    {:keep_state_and_data, reply(from, :ok)}
  end

  def handle_event({:call, from}, {:attach_parent, parent}, _phase, data) do
    cond do
      data.parent != nil ->
        {:keep_state_and_data, reply(from, {:error, :already_attached})}

      data.parent_effect != nil ->
        {:keep_state_and_data, reply(from, {:error, :orphan_dispatch_pending})}

      parent.jido != data.jido or parent.partition != data.partition or is_nil(data.jido) ->
        {:keep_state_and_data, reply(from, {:error, :different_instance})}

      data.activation == parent.activation ->
        {:keep_state_and_data, reply(from, {:error, :self_adoption})}

      true ->
        case ServerSupervisor.record_child(parent, data.activation, false) do
          :ok ->
            :ets.insert(data.activation_state, {:parent, parent})
            parent = Map.put(parent, :monitor, Process.monitor(parent.activation))
            {:keep_state, %{data | parent: parent}, reply(from, :ok)}

          error ->
            {:keep_state_and_data, reply(from, error)}
        end
    end
  end

  def handle_event({:call, from}, :parent, _phase, data),
    do: {:keep_state_and_data, reply(from, public_parent(data.parent))}

  def handle_event({:call, from}, :activation, _phase, data),
    do: {:keep_state_and_data, reply(from, data.activation)}

  def handle_event({:call, from}, :stop_target, _phase, data) do
    result =
      if control_caller?(from, data),
        do: {:error, :reentrant_turn},
        else: data.activation

    {:keep_state_and_data, reply(from, result)}
  end

  def handle_event({:call, from}, {:control, kind, policy, timeout}, phase, data) do
    cond do
      control_caller?(from, data) ->
        {:keep_state_and_data, reply(from, {:error, :reentrant_turn})}

      phase in [:restoring, :initializing] ->
        {:keep_state_and_data, reply(from, {:error, :not_ready})}

      data.control != nil ->
        {:keep_state_and_data, reply(from, {:error, :control_in_progress})}

      data.admission_mode == :blocked ->
        {:keep_state_and_data, reply(from, {:error, :unsafe_resume})}

      kind == :hibernate and data.persistence in [nil, false] ->
        {:keep_state_and_data, reply(from, Durable.error(:persistence_not_configured, true))}

      true ->
        begin_control(phase, data, kind, from, policy, timeout)
    end
  end

  def handle_event({:call, from}, :resume, phase, data) do
    result =
      cond do
        control_caller?(from, data) -> {:error, :reentrant_turn}
        phase in [:restoring, :initializing] -> {:error, :not_ready}
        data.admission_mode == :blocked -> {:error, :unsafe_resume}
        data.control != nil or not settled?(data) -> {:error, :not_quiescent}
        true -> :ok
      end

    if result == :ok,
      do: {:keep_state, data |> set_admission(:open) |> arm_idle(), reply(from, :ok)},
      else: {:keep_state_and_data, reply(from, result)}
  end

  def handle_event({:call, from}, {kind, owner}, phase, data) when kind in [:attach, :detach] do
    owners =
      case {kind, Map.fetch(data.owners, owner)} do
        {:attach, :error} ->
          Map.put(data.owners, owner, Process.monitor(owner))

        {:detach, {:ok, ref}} ->
          Process.demonitor(ref, [:flush])
          Map.delete(data.owners, owner)

        _ ->
          data.owners
      end

    persist_runtime(data.activation_state, :owners, Map.keys(owners))
    data = cancel_idle(%{data | owners: owners})
    data = if phase == :idle, do: arm_idle(data), else: data
    {:keep_state, data, reply(from, :ok)}
  end

  def handle_event({:call, from}, :touch, phase, data) do
    data = cancel_idle(data)
    data = if phase == :idle, do: arm_idle(data), else: data
    {:keep_state, data, reply(from, :ok)}
  end

  def handle_event(:internal, :control_progress, _phase, data), do: control_progress(data)

  def handle_event(:info, {:control_timeout, token}, _phase, %{control: %{token: token}} = data) do
    control_timeout(data)
  end

  def handle_event(:info, {ref, result}, _phase, %{control: %{task: %{ref: ref}}} = data) do
    complete_task(data.control.task)

    case Durable.write_result(result, data.control.deadline) do
      :ok ->
        Process.cancel_timer(data.control.timer)
        # The caller installs its monitor before requesting save. Reply only
        # after save; it confirms the activation DOWN before returning success.
        replies = reply(data.control.from, :saved)
        {:stop_and_reply, {:shutdown, :hibernate}, replies, %{data | control: nil}}

      {:error, reason} ->
        control_failed(data, reason, Durable.resumable?(reason))
    end
  end

  def handle_event(
        :info,
        {:DOWN, ref, :process, _, _},
        _phase,
        %{control: %{task: %{ref: ref}}} = data
      ),
      do: control_failed(data, :indeterminate, false)

  def handle_event(:info, {:DOWN, ref, :process, owner, _}, phase, data)
      when is_map_key(data.owners, owner) and :erlang.map_get(owner, data.owners) == ref do
    owners = Map.delete(data.owners, owner)
    persist_runtime(data.activation_state, :owners, Map.keys(owners))
    data = cancel_idle(%{data | owners: owners})
    {:keep_state, if(phase == :idle, do: arm_idle(data), else: data)}
  end

  def handle_event(:info, {:idle_timeout, token}, :idle, %{idle_timer: {_, token}} = data) do
    data = %{data | idle_timer: nil}

    if map_size(data.owners) == 0 and data.admission_mode == :open and settled?(data) do
      case data.idle_policy do
        :stop ->
          {:stop, {:shutdown, :idle_timeout}, data}

        :hibernate ->
          begin_control(:idle, data, :hibernate, nil, :finish, data.persistence_timeout)
      end
    else
      :keep_state_and_data
    end
  end

  # A recovery group can restart a Plugin while the worker still loads its
  # durable checkpoint. Do not give that Plugin the supplied initial state.
  def handle_event(
        {:call, _from},
        {kind, _package},
        :restoring,
        %{bootstrap: %{kind: :persistence}}
      )
      when kind in [:plugin_init, :plugin_start],
      do: {:keep_state_and_data, [:postpone]}

  def handle_event({:call, from}, {kind, package}, _phase, data)
      when kind in [:plugin_init, :plugin_start] do
    spec = Enum.find(data.plugin_specs, &(&1.module == package))

    result =
      cond do
        is_nil(spec) -> {:error, :plugin_not_found}
        kind == :plugin_init -> {:ok, Plugin.init(data, spec, self())}
        true -> {:ok, Plugin.init(data, spec, self()), spec}
      end

    {:keep_state_and_data, reply(from, result)}
  end

  def handle_event({:call, from}, :snapshot, phase, _data)
      when phase in [:initializing, :restoring],
      do: {:keep_state_and_data, reply(from, {:error, :not_ready})}

  def handle_event({:call, from}, :snapshot, _phase, data),
    do: {:keep_state_and_data, reply(from, Durable.snapshot(data.agent, data.state_version))}

  def handle_event({:call, from}, {:upgrade, token, action, context}, :idle, data) do
    data = %{
      data
      | postponed: MapSet.delete(data.postponed, token),
        queued_from: Map.delete(data.queued_from, token)
    }

    if data.admission_mode == :open do
      signal = Signal.new!("jido.agent_server.upgrade", %{}, source: "/agent_server")
      start_turn({:call, from}, signal, context, data, {:upgrade, action})
    else
      reject_turn({:call, from}, {:not_admitting, data.admission_mode}, data)
    end
  end

  def handle_event({:call, from}, {:upgrade, token, _action, _context}, _phase, data) do
    if Core.reentrant?({:call, from}, data) or Core.bootstrap_caller?(from, data),
      do: reject_turn({:call, from}, :reentrant_turn, data),
      else: postpone_turn({:call, from}, token, data)
  end

  def handle_event(:cast, {kind, _source, _signal}, phase, data)
      when kind in [:topology_output, :topology_bus] and
             (phase in [:initializing, :restoring] or
                (phase == :effects and is_map(data.active) and
                   :erlang.is_map_key(:reconciling, data.active) and
                   :erlang.map_get(:reconciling, data.active) == true)),
      do: {:keep_state_and_data, [:postpone]}

  def handle_event(:cast, {:topology_output, tag, signal}, _phase, data) do
    case TopologyRuntime.member_output(Map.put(data, :server, self()), tag, signal) do
      :ok -> :keep_state_and_data
      {:error, reason} -> {:stop, {:shutdown, {:topology_delivery_failed, reason}}, data}
    end
  end

  def handle_event(:cast, {:topology_bus, name, signal}, _phase, data) do
    case TopologyRuntime.output(Map.put(data, :server, self()), %{kind: :bus, name: name}, signal) do
      :ok -> :keep_state_and_data
      {:error, reason} -> {:stop, {:shutdown, {:topology_delivery_failed, reason}}, data}
    end
  end

  def handle_event({:call, from}, :agent, _phase, data),
    do: {:keep_state_and_data, [{:reply, from, data.agent}]}

  def handle_event({:call, from}, :await_ready, phase, data)
      when phase in [:restoring, :initializing] do
    {caller, _} = from

    if Core.owned_process?(caller, data.bootstrap.task.pid, [], 0) do
      {:keep_state_and_data, reply(from, {:error, :reentrant_turn})}
    else
      {:keep_state, %{data | ready_waiters: [from | data.ready_waiters]}}
    end
  end

  def handle_event({:call, from}, :await_ready, :effects, %{active: %{reconciling: true}} = data) do
    if Core.reentrant?({:call, from}, data),
      do: {:keep_state_and_data, reply(from, {:error, :reentrant_turn})},
      else: {:keep_state, %{data | ready_waiters: [from | data.ready_waiters]}}
  end

  def handle_event({:call, from}, :await_ready, _phase, _data),
    do: {:keep_state_and_data, reply(from, :ok)}

  def handle_event({:call, from}, {:plugin_state, package}, _phase, data) do
    result =
      case Enum.find(data.plugin_specs, &(&1.module == package)) do
        nil -> {:error, :plugin_not_found}
        spec -> {:ok, Plugin.owned_state(data.agent, spec)}
      end

    {:keep_state_and_data, reply(from, result)}
  end

  def handle_event(type, {:turn, _token, _signal, _context, _deadline, reply_gate}, phase, data)
      when phase in [:restoring, :initializing],
      do: reject_turn(type, :not_ready, data, reply_gate)

  def handle_event({:call, from}, {:cancel, _id}, phase, _data)
      when phase in [:restoring, :initializing],
      do: {:keep_state_and_data, reply(from, {:error, :not_running})}

  def handle_event(:info, {ref, result}, phase, %{bootstrap: %{task: %{ref: ref}}} = data)
      when phase in [:restoring, :initializing] do
    complete_task(data.bootstrap.task)
    Process.cancel_timer(data.bootstrap.timer)

    if System.monotonic_time(:millisecond) >= data.bootstrap.deadline do
      {:stop, {:shutdown, bootstrap_timeout(data)}, data}
    else
      finish_bootstrap(result, data)
    end
  end

  def handle_event(
        :info,
        {:readiness_timeout, token},
        phase,
        %{bootstrap: %{token: token}} = data
      )
      when phase in [:restoring, :initializing],
      do: {:stop, {:shutdown, bootstrap_timeout(data)}, data}

  def handle_event(
        :info,
        {:DOWN, ref, :process, _pid, _reason},
        phase,
        %{bootstrap: %{task: %{ref: ref}}} = data
      )
      when phase in [:restoring, :initializing],
      do: {:stop, {:shutdown, :plugin_start_failed}, data}

  def handle_event({:call, from}, :history, _phase, data),
    do: {:keep_state_and_data, reply(from, :queue.to_list(data.history))}

  def handle_event({:call, from}, :status, phase, data) do
    {:message_queue_len, mailbox} = Process.info(self(), :message_queue_len)

    status = %{
      phase:
        case phase do
          phase when phase in [:restoring, :initializing] -> :initializing
          :idle -> :idle
          :waiting -> :waiting
          _ -> :running
        end,
      ready?:
        phase not in [:restoring, :initializing] and not match?(%{reconciling: true}, data.active),
      plugin_count: length(data.plugin_specs),
      activation: data.activation,
      generation: data.generation,
      parent: public_parent(data.parent),
      agent_id: data.agent.id,
      jido: data.jido,
      partition: data.partition,
      effects: Effects.status(data.active),
      last_effect_outcome: data.last_effect_outcome,
      state_version: data.state_version,
      durable_turn:
        if(data.server_turn, do: Map.take(data.server_turn, [:id, :status]), else: nil),
      error_count: data.error_count,
      last_outcome: data.last_outcome,
      owners: Map.keys(data.owners),
      idle_timeout: data.idle_timeout,
      idle_policy: data.idle_policy,
      admission: %{
        mode: data.admission_mode,
        postponed: MapSet.size(data.postponed),
        limit: data.max_postponed_signals,
        message_queue_len: mailbox
      },
      active: Core.active_status(data.active, phase),
      waits: if(data.active, do: data.active.waits, else: [])
    }

    {:keep_state_and_data, [{:reply, from, status}]}
  end

  def handle_event(
        {:call, from},
        {:wait_input, input},
        :waiting,
        %{active: %{operation: nil}} = data
      )
      when data.admission_mode != :blocked and
             (is_nil(data.control) or data.control.kind == :quiesce) do
    data = data |> cancel_wait_timer() |> put_in([:active, :wait_from], from)
    durable_operation(:durable_input, data, fn -> DurableTurn.deliver(data, input) end)
  end

  def handle_event({:call, from}, {:wait_input, _input}, _phase, _data),
    do: {:keep_state_and_data, reply(from, {:error, :not_waiting})}

  def handle_event({:call, from}, {:cancel, _id}, :idle, _data),
    do: {:keep_state_and_data, reply(from, {:error, :not_running})}

  def handle_event({:call, from}, {:cancel, _id}, :waiting, %{admission_mode: :blocked}),
    do: {:keep_state_and_data, reply(from, {:error, :unsafe_resume})}

  def handle_event({:call, from}, {:cancel, _id}, phase, _data)
      when phase in [:saving, :hibernating],
      do: {:keep_state_and_data, reply(from, {:error, :commit_in_progress})}

  def handle_event({:call, from}, {:cancel, _id}, phase, _data) when phase in [:policy, :effects],
    do: {:keep_state_and_data, reply(from, {:error, :not_running})}

  def handle_event(:info, {:turn_timeout, _id}, phase, _data)
      when phase in [:saving, :hibernating, :policy, :effects],
      do: :keep_state_and_data

  def handle_event(:info, {:turn_timeout, _id}, :waiting, %{admission_mode: :blocked}),
    do: :keep_state_and_data

  def handle_event(:info, {:persistence_timeout, id}, :saving, %{active: %{turn_id: id}} = data),
    do: stop_durable(data, :indeterminate)

  def handle_event(
        :info,
        {:composition_timeout, id},
        :effects,
        %{active: %{turn_id: id, reconciling: true}} = data
      ),
      do:
        stop_failed(
          data,
          execution_error("Composition readiness timed out", :composition_timeout),
          :effects
        )

  def handle_event(:internal, :effect_next, :effects, data), do: next_effect(data)

  def handle_event(
        :info,
        {:commit_timeout, id},
        :effects,
        %{active: %{turn_id: id, commit_hooks: [_ | _]}} = data
      ) do
    if data.active.operation, do: Task.shutdown(data.active.operation.task, :brutal_kill)
    finish_effects(put_in(data.active.operation, nil), :timed_out)
  end

  def handle_event(
        :info,
        {:effect_timeout, id},
        :effects,
        %{active: %{turn_id: id, commit_hooks: []}} = data
      ) do
    if data.active.operation, do: Task.shutdown(data.active.operation.task, :brutal_kill)
    finish_effects(put_in(data.active.operation, nil), :timed_out)
  end

  def handle_event(:info, {:policy_timeout, id}, :policy, %{active: %{turn_id: id}} = data) do
    Task.shutdown(data.active.operation.task, :brutal_kill)
    complete_terminal(put_in(data.active.operation, nil), {:stop, :error_policy_timeout})
  end

  def handle_event({:call, from} = type, {:cancel, id}, phase, data) do
    cond do
      id != :active and id != data.active.turn_id ->
        {:keep_state_and_data, reply(from, {:error, :stale_turn})}

      Core.reentrant?(type, data) ->
        {:keep_state_and_data, reply(from, {:error, :reentrant_turn})}

      true ->
        data = update_in(data.active.cancel_waiters, &[from | &1])
        abort_turn(phase, data, :cancelled)
    end
  end

  def handle_event(:info, {:turn_timeout, id}, phase, %{active: %{turn_id: id}} = data) do
    cond do
      data.active.deadline == :infinity ->
        :keep_state_and_data

      expired?(data.active) ->
        abort_turn(phase, data, :turn_timeout)

      true ->
        cancel_timer(data.active)
        remaining = remaining_wait(data.active.deadline)

        timer =
          Process.send_after(self(), {:turn_timeout, id}, min(remaining, Core.max_timeout()))

        {:keep_state, put_in(data.active.timer, timer)}
    end
  end

  def handle_event(type, {:turn, token, _signal, _context, _deadline, reply_gate}, _phase, data)
      when data.admission_mode != :open do
    queued? = MapSet.member?(data.postponed, token)
    data = %{data | postponed: MapSet.delete(data.postponed, token)}

    replies =
      if queued? do
        []
      else
        ReplyGate.done(reply_gate)
        turn_rejection(type, :quiesced, data)
      end

    {:keep_state, data, replies ++ [{:next_event, :internal, :control_progress}]}
  end

  def handle_event(type, {:turn, token, signal, context, deadline, reply_gate}, :idle, data)
      when type == :cast or (is_tuple(type) and elem(type, 0) == :call) do
    data = %{
      data
      | postponed: MapSet.delete(data.postponed, token),
        queued_from: Map.delete(data.queued_from, token)
    }

    case Core.admission_status(deadline) do
      :ok -> start_turn(type, signal, context, data, :turn, reply_gate)
      {:error, reason} -> reject_turn(type, reason, data, reply_gate)
    end
  end

  def handle_event(type, {:turn, token, _signal, _context, deadline, reply_gate}, phase, data)
      when phase in [
             :preparing,
             :starting,
             :running,
             :waiting,
             :hibernating,
             :settling,
             :cleaning,
             :reconfiguring,
             :saving,
             :policy,
             :effects
           ] and
             (type == :cast or (is_tuple(type) and elem(type, 0) == :call)) do
    admission =
      if Core.reentrant?(type, data),
        do: {:error, :reentrant_turn},
        else: Core.admission_status(deadline)

    case admission do
      {:error, reason} ->
        reject_turn(
          type,
          reason,
          %{
            data
            | postponed: MapSet.delete(data.postponed, token),
              queued_from: Map.delete(data.queued_from, token)
          },
          reply_gate
        )

      :ok ->
        postpone_turn(type, token, data, reply_gate)
    end
  end

  def handle_event(
        :info,
        {ref, result},
        phase,
        %{active: %{operation: %{task: %{ref: ref}} = operation}} = data
      ) do
    complete_task(operation.task)

    storage_expired =
      if operation.kind in [
           :durable_accept,
           :durable_terminal,
           :durable_advance,
           :durable_start,
           :durable_suspend,
           :durable_input
         ] do
        {timer, deadline} = data.active.durable_storage
        Process.cancel_timer(timer)
        System.monotonic_time(:millisecond) >= deadline
      else
        false
      end

    data = put_in(data.active.operation, nil)

    cond do
      storage_expired ->
        stop_durable(data, :indeterminate)

      phase not in [:cleaning, :saving, :policy, :effects] and expired?(data.active) ->
        abort_turn(phase, data, :turn_timeout)

      true ->
        operation_result(operation.kind, result, data)
    end
  end

  def handle_event(:info, {:worker_complete, id}, :starting, %{active: %{turn_id: id}}),
    do: {:keep_state_and_data, [:postpone]}

  def handle_event(:info, {:worker_complete, id}, :running, %{active: %{turn_id: id}} = data) do
    active = data.active
    runner = data.runner

    config =
      data
      |> Map.take([
        :directive_handler,
        :max_directives_per_turn,
        :default_dispatch,
        :jido,
        :plugin_specs,
        :plugin_refs,
        :agent,
        :activation,
        :activation_state,
        :parent,
        :runner,
        :partition
      ])
      |> Map.put(:requester, active.requester)

    operation(:settle, data, fn -> settle_worker(runner, active, config) end)
  end

  def handle_event(:info, {:DOWN, ref, :process, _pid, _reason}, phase, data)
      when is_map_key(data.instance_monitors, ref),
      do: stop_failed(data, execution_error("Instance ownership stopped", :instance_lost), phase)

  def handle_event(
        :info,
        {:DOWN, ref, :process, _pid, reason},
        phase,
        %{runner_ref: ref} = data
      ),
      do: stop_failed(data, execution_error("Runic Runner stopped", reason), phase)

  def handle_event(
        :info,
        {:DOWN, ref, :process, _pid, reason},
        phase,
        %{active: %{operation: %{task: %{ref: ref}}}} = data
      ),
      do: stop_failed(data, execution_error("Turn lifecycle task stopped", reason), phase)

  # Cleanup cancels the Worker. Its DOWN can arrive before the task result.
  def handle_event(:info, {:DOWN, ref, :process, _pid, _reason}, :cleaning, %{
        active: %{worker_ref: ref}
      }),
      do: :keep_state_and_data

  def handle_event(
        :info,
        {:DOWN, ref, :process, _pid, reason},
        _phase,
        %{active: %{worker_ref: ref, durable: true}} = data
      ),
      do: {:stop, {:durable_worker_lost, reason}, data}

  def handle_event(
        :info,
        {:DOWN, ref, :process, _pid, reason},
        phase,
        %{active: %{worker_ref: ref}} = data
      ),
      do: stop_failed(data, execution_error("Owned Runic Worker stopped", reason), phase)

  def handle_event(
        :info,
        {:DOWN, ref, :process, _pid, reason},
        _phase,
        %{parent: %{monitor: ref}} = data
      ) do
    parent = data.parent
    :ets.insert(data.activation_state, {:parent, nil})
    data = %{data | parent: nil}

    case parent.policy do
      :stop ->
        {:stop, {:shutdown, :parent_down}, data}

      :continue ->
        {:keep_state, data}

      :emit_orphan ->
        signal =
          Signal.new!(
            "jido.agent_server.orphaned",
            %{parent_id: parent.agent_id, tag: parent.tag, reason: inspect(reason)},
            source: "/agent/" <> data.agent.id
          )

        dispatch = DispatchPreparation.inherit_bus_scope(parent.dispatch, data.jido)
        task = Task.async(fn -> Jido.Signal.Dispatch.dispatch(signal, dispatch) end)
        timer = Process.send_after(self(), {:orphan_timeout, task.ref}, data.directive_timeout)

        {:keep_state,
         %{
           data
           | parent_effect: %{
               task: task,
               timer: timer,
               deadline: System.monotonic_time(:millisecond) + data.directive_timeout
             }
         }}
    end
  end

  def handle_event(:info, {ref, result}, _phase, %{parent_effect: %{task: %{ref: ref}}} = data) do
    complete_task(data.parent_effect.task)
    Process.cancel_timer(data.parent_effect.timer)
    expired = System.monotonic_time(:millisecond) >= data.parent_effect.deadline
    data = %{data | parent_effect: nil}

    if result == :ok and not expired,
      do: {:keep_state, data, [{:next_event, :internal, :control_progress}]},
      else: {:stop, {:shutdown, :orphan_dispatch_failed}, data}
  end

  def handle_event(
        :info,
        {:orphan_timeout, ref},
        _phase,
        %{parent_effect: %{task: %{ref: ref}}} = data
      ),
      do: {:stop, {:shutdown, :orphan_dispatch_timeout}, data}

  def handle_event(
        :info,
        {:DOWN, ref, :process, _, _},
        _phase,
        %{parent_effect: %{task: %{ref: ref}}} = data
      ),
      do: {:stop, {:shutdown, :orphan_dispatch_failed}, data}

  def handle_event(:info, {:child_registered, tag, token, root}, _phase, data) do
    case :ets.lookup(data.activation_state, {:child, tag}) do
      [{_, %{token: ^token, root: ^root}}] ->
        monitors = forget_child_monitors(data.child_monitors, tag, token)
        monitors = Map.put(monitors, Process.monitor(root), {:root, tag, token})
        {:keep_state, %{data | child_monitors: monitors}}

      _ ->
        :keep_state_and_data
    end
  end

  def handle_event(:info, {:child_released, tag, token}, _phase, data),
    do:
      {:keep_state,
       %{data | child_monitors: forget_child_monitors(data.child_monitors, tag, token)}}

  def handle_event(:info, {:DOWN, ref, :process, pid, reason}, _phase, data)
      when is_map_key(data.child_monitors, ref) do
    {{kind, tag, token}, monitors} = Map.pop(data.child_monitors, ref)

    case :ets.lookup(data.activation_state, {:child, tag}) do
      [{_, %{root: _root}}] when kind == :reservation ->
        :ok

      [{_, %{token: ^token, caller: ^pid} = record}] when kind == :reservation ->
        :ets.delete_object(data.activation_state, {{:child, tag}, record})

      [{_, %{token: ^token, root: ^pid} = record}] ->
        if record.restart? == false or
             (Map.get(record, :restart, :transient) != :permanent and
                (reason in [:normal, :shutdown] or match?({:shutdown, _}, reason))),
           do: :ets.delete_object(data.activation_state, {{:child, tag}, record})

      _ ->
        :ok
    end

    {:keep_state, %{data | child_monitors: monitors}}
  end

  def handle_event(
        :internal,
        :recover_turn,
        :idle,
        %{server_turn: %{status: :running} = receipt} = data
      ) do
    start_turn(
      :cast,
      receipt.signal,
      receipt.context,
      data,
      {:restore, receipt}
    )
  end

  def handle_event(:internal, :recover_turn, _phase, _data), do: :keep_state_and_data

  def handle_event(:info, {:durable_advance, id}, :starting, %{active: %{turn_id: id}}),
    do: {:keep_state_and_data, [:postpone]}

  def handle_event(:info, {:durable_advance, id}, :running, %{active: %{turn_id: id}} = data),
    do: durable_advance(data)

  def handle_event(:internal, :durable_advance, :running, data), do: durable_advance(data)

  def handle_event(
        :info,
        {:wait_wake, id, token},
        :waiting,
        %{active: %{turn_id: id, wait_token: token, operation: nil}} = data
      )
      when data.admission_mode != :blocked and
             (is_nil(data.control) or data.control.kind == :quiesce),
      do: start_durable_worker(cancel_wait_timer(data))

  def handle_event(
        :info,
        {:durable_storage_timeout, id},
        _phase,
        %{active: %{turn_id: id}} = data
      ),
      do: stop_durable(data, :indeterminate)

  def handle_event(:info, _message, _phase, _data), do: :keep_state_and_data

  defp bootstrap_timeout(%{bootstrap: %{kind: :persistence}}), do: :persistence_timeout
  defp bootstrap_timeout(_data), do: :readiness_timeout

  defp finish_bootstrap(
         {:ok, agent, revision, config, turn},
         %{bootstrap: %{kind: :persistence}} = data
       ) do
    Durable.restore(data.activation_state, agent, revision)
    {:ok, specs} = Jido.Plugin.Normalizer.normalize_all(Jido.Agent.runtime_plugins(agent))

    data = %{
      data
      | agent: agent,
        plugin_specs: specs,
        state_version: revision,
        persistence: config,
        server_turn: turn,
        bootstrap: nil
    }

    case initialize_plugins(data) do
      {:ok, phase, next} -> {:next_state, phase, next}
      {:ok, phase, next, actions} -> {:next_state, phase, next, actions}
    end
  end

  defp finish_bootstrap({:ok, refs}, %{bootstrap: %{kind: :plugins}} = data) do
    mark_ready(data)
    replies = Enum.flat_map(data.ready_waiters, &reply(&1, :ok))
    idle_transition(%{data | bootstrap: nil, plugin_refs: refs, ready_waiters: []}, replies)
  end

  defp finish_bootstrap({:error, reason}, data),
    do: {:stop, {:shutdown, reason}, data}

  @impl true
  def terminate(_reason, phase, data) do
    cancel_idle(data)

    if data.control do
      Process.cancel_timer(data.control.timer)
      if data.control.task, do: Task.shutdown(data.control.task, :brutal_kill)
    end

    if data.parent_effect do
      Process.cancel_timer(data.parent_effect.timer)
      Task.shutdown(data.parent_effect.task, :brutal_kill)
    end

    if data.bootstrap do
      Process.cancel_timer(data.bootstrap.timer)
      Task.shutdown(data.bootstrap.task, :brutal_kill)
    end

    if data.active do
      if data.active.wait_timer, do: Process.cancel_timer(data.active.wait_timer)
      if data.active.operation, do: Task.shutdown(data.active.operation.task, :brutal_kill)

      if phase == :effects and is_nil(data.active.effect_outcome),
        do: record_effects(data, :indeterminate)

      unless data.active.outcome do
        record_outcome(data, :indeterminate, phase, false, 0)
      end

      # Runic also stops owned execution after abrupt owner death.
      try do
        Runner.cancel(data.runner, data.active.worker_id)
      catch
        :exit, _ -> :ok
      end
    end

    TraceContext.clear()
    Semantic.point([:jido, :agent_server, :lifecycle, :stop], %{agent_id: data.agent.id})
    :ok
  end

  defp start_turn(type, signal, context, data, mode, reply_gate \\ nil) do
    data = cancel_idle(data)

    from =
      case type do
        {:call, from} -> from
        :cast -> nil
      end

    turn_id =
      case mode do
        {:restore, receipt} -> receipt.id
        _ -> Jido.Signal.ID.generate!()
      end

    timeout =
      case mode do
        {:restore, %{expires_at: :infinity}} -> :infinity
        {:restore, receipt} -> max(0, receipt.expires_at - System.system_time(:millisecond))
        _ -> data.turn_timeout
      end

    agent = data.agent
    trace = TraceContext.begin_turn(signal)

    span =
      Semantic.start(
        [:jido, :agent_server, :turn],
        Map.merge(trace, %{agent_id: agent.id, turn_id: turn_id, signal_id: signal.id})
      )

    TraceContext.put(span.trace)
    context = context |> Map.put(:turn_id, turn_id) |> Map.put(:trace_context, span.trace)

    active = %{
      from: from,
      requester: reply_gate,
      span: span,
      signal_type: signal.type,
      outcome: nil,
      effects: [],
      effect_index: 0,
      effect_timer: nil,
      effect_deadline: nil,
      effect_outcome: nil,
      failure_stage: nil,
      policy_timer: nil,
      policy_deadline: nil,
      turn_id: turn_id,
      signal_id: signal.id,
      source_signal: signal,
      turn_context: Map.drop(context, [:turn_id, :trace_context]),
      commit_hooks: [],
      start_version: data.state_version,
      prepared: nil,
      operation: nil,
      worker: nil,
      worker_ref: nil,
      execution_id: nil,
      worker_id: turn_id,
      durable: match?({:restore, _}, mode),
      durable_finalized: false,
      durable_storage: nil,
      durable_next: nil,
      advance_pending: false,
      waits: [],
      wait_deadline: nil,
      wait_timer: nil,
      wait_token: nil,
      wait_from: nil,
      result: nil,
      abort_reason: nil,
      cancel_waiters: [],
      deadline:
        if(timeout == :infinity,
          do: :infinity,
          else: System.monotonic_time(:millisecond) + timeout
        ),
      timer:
        if(timeout == :infinity,
          do: nil,
          else:
            Process.send_after(self(), {:turn_timeout, turn_id}, min(timeout, Core.max_timeout()))
        )
    }

    case mode do
      {:restore, receipt} ->
        operation(:restore_turn, %{data | active: active}, fn ->
          DurableTurn.restore(agent, receipt, context, data.plugin_specs)
        end)

      :turn ->
        operation(:prepare, %{data | active: active}, fn ->
          prepare_turn(agent, signal, context, data)
        end)

      {:upgrade, action} ->
        operation(:upgrade, %{data | active: active}, fn ->
          with {:ok, candidate} <- Durable.upgrade(agent, action, context),
               {:ok, candidate} <- Jido.Agent.Composition.bind(candidate),
               :ok <- CompositionRuntime.check(data, candidate, []) do
            {:ok, candidate, []}
          end
        end)
    end
  end

  defp prepare_turn(agent, signal, context, data) do
    with {:ok, inputs} <- Jido.Agent.Plugin.prepare(agent, signal, data.plugin_specs),
         {:ok, command} <- Command.new_trusted_agent(agent, signal, context),
         command = %{command | plugin_inputs: inputs},
         {:ok, admitted} <- Plugin.admit(command, data),
         {:ok, prepared} <-
           AgentRunner.prepare_for_server(admitted, signal, [], data.plugin_specs) do
      {:ok, prepared}
    else
      {:error, _stage, reason} -> {:error, reason}
      {:error, _} = error -> error
    end
  end

  defp durable_write(kind, data, agent, receipt) do
    durable_operation(kind, data, fn ->
      Durable.save(data, agent, data.state_version + 1, data.state_version, receipt)
    end)
  end

  defp durable_operation(kind, data, fun) do
    timer =
      Process.send_after(
        self(),
        {:durable_storage_timeout, data.active.turn_id},
        data.persistence_timeout
      )

    operation(
      kind,
      put_in(
        data.active.durable_storage,
        {timer, System.monotonic_time(:millisecond) + data.persistence_timeout}
      ),
      fun
    )
  end

  defp publish_durable_revision(data) do
    case ServerSupervisor.publish_checkpoint(
           data.activation_state,
           data.agent,
           data.state_version + 1
         ) do
      :ok -> {:ok, %{data | state_version: data.state_version + 1}}
      error -> error
    end
  end

  defp start_durable_worker(data) do
    data = put_in(data.active.worker_id, DurableTurn.identity(data))
    owner = self()
    hooks = Core.execution_hooks(Keyword.get(data.exec_opts, :hooks, []), TraceContext.get())
    policy = Core.execution_policy(data.exec_opts)

    durable_operation(:durable_start, data, fn ->
      DurableTurn.start(data, owner, hooks, policy)
    end)
  end

  defp durable_advance(%{active: %{operation: nil}} = data),
    do:
      durable_operation(:durable_advance, data, fn ->
        DurableTurn.advance(data.runner, data.active.worker_id)
      end)

  defp durable_advance(data), do: {:keep_state, put_in(data.active.advance_pending, true)}

  defp operation(kind, data, fun) do
    captured = TraceContext.capture()
    task = Task.async(fn -> TraceContext.with_context(captured, fun) end)

    phases = %{
      upgrade: :preparing,
      prepare: :preparing,
      restore_turn: :preparing,
      durable_accept: :saving,
      durable_start: :starting,
      durable_advance: :running,
      durable_terminal: :saving,
      durable_suspend: :starting,
      durable_input: :starting,
      start: :starting,
      execute: :starting,
      settle: :settling,
      cleanup: :cleaning,
      reconfigure: :reconfiguring,
      resume_plugins: :cleaning,
      reconcile: :effects,
      save: :saving,
      policy: :policy,
      commit_hook: :effects,
      effect: :effects
    }

    {:next_state, Map.fetch!(phases, kind),
     put_in(data.active.operation, %{kind: kind, task: task})}
  end

  defp operation_result(:upgrade, result, data), do: finish(data, result)

  defp operation_result(kind, {:ok, prepared}, data) when kind in [:prepare, :restore_turn] do
    data = put_in(data.active.prepared, prepared)

    case DurableTurn.instruction(prepared) do
      {:ok, %{kind: :flow}} when data.persistence not in [nil, false] ->
        if kind == :restore_turn do
          start_durable_worker(data)
        else
          case DurableTurn.accept(data, prepared) do
            {:ok, receipt} ->
              data = %{data | server_turn: receipt, active: %{data.active | durable: true}}
              durable_write(:durable_accept, data, data.agent, receipt)

            {:error, reason} ->
              cleanup(data, {:error, reason})
          end
        end

      _ ->
        owner = self()
        runner = data.runner
        id = data.active.turn_id
        exec_opts = data.exec_opts
        operation(:start, data, fn -> start_worker(runner, id, owner, prepared, exec_opts) end)
    end
  end

  defp operation_result(:restore_turn, {:error, reason}, data), do: stop_durable(data, reason)

  defp operation_result(:durable_accept, :ok, data) do
    case publish_durable_revision(data) do
      {:ok, data} -> start_durable_worker(data)
      {:error, reason} -> stop_durable(data, reason)
    end
  end

  defp operation_result(:durable_start, {:ok, worker, id}, data) do
    active = %{
      data.active
      | worker: worker,
        worker_ref: Process.monitor(worker),
        worker_id: id,
        waits: [],
        wait_deadline: nil
    }

    case ServerSupervisor.remember_execution(data.activation_state, data.runner, id, worker) do
      :ok ->
        {:next_state, :running, %{data | active: active},
         [{:next_event, :internal, :durable_advance}]}

      {:error, reason} ->
        stop_durable(%{data | active: active}, reason)
    end
  end

  defp operation_result(:durable_start, {:waiting, waits, deadline}, data),
    do: wait_for_input(data, waits, deadline)

  defp operation_result(:durable_advance, {:waiting, waits, deadline}, data) do
    if data.active.worker_ref, do: Process.demonitor(data.active.worker_ref, [:flush])

    data =
      data
      |> put_in([:active, :worker], nil)
      |> put_in([:active, :worker_ref], nil)
      |> put_in([:active, :waits], waits)
      |> put_in([:active, :wait_deadline], deadline)

    durable_operation(:durable_suspend, data, fn ->
      DurableTurn.suspend(data.runner, data.active.worker_id)
    end)
  end

  defp operation_result(:durable_suspend, :ok, data) do
    ServerSupervisor.forget_execution(data.activation_state)
    wait_for_input(data, data.active.waits, data.active.wait_deadline)
  end

  defp operation_result(:durable_input, :ok, data) do
    from = data.active.wait_from
    data = put_in(data.active.wait_from, nil)
    {:next_state, phase, data} = start_durable_worker(data)
    {:next_state, phase, data, reply(from, :ok)}
  end

  defp operation_result(:durable_input, {:rejected, reason}, data) do
    from = data.active.wait_from
    data = data |> put_in([:active, :wait_from], nil) |> arm_wait_timer()
    {:next_state, :waiting, data, reply(from, {:error, reason})}
  end

  defp operation_result(:durable_advance, :running, data) do
    pending = Map.get(data.active, :advance_pending, false)
    data = put_in(data.active.advance_pending, false)

    {:next_state, :running, data,
     if(pending, do: [{:next_event, :internal, :durable_advance}], else: [])}
  end

  defp operation_result(:durable_advance, :complete, data),
    do: handle_event(:info, {:worker_complete, data.active.turn_id}, :running, data)

  defp operation_result(:durable_terminal, :ok, data) do
    case publish_durable_revision(data) do
      {:ok, data} ->
        data = put_in(data.active.durable_finalized, true)

        case data.active.durable_next do
          {:finish, result} -> finish(data, result)
          {:abort, phase, reason} -> abort_turn(phase, data, reason)
        end

      {:error, reason} ->
        stop_durable(data, reason)
    end
  end

  defp operation_result(:durable_advance, {:error, :non_portable_flow_output}, data),
    do:
      cleanup(
        data,
        {:error, execution_error("Flow output is not portable data", :non_portable_flow_output)}
      )

  defp operation_result(kind, {:error, reason}, data)
       when kind in [
              :durable_accept,
              :durable_start,
              :durable_advance,
              :durable_terminal,
              :durable_suspend,
              :durable_input
            ],
       do: stop_durable(data, reason)

  defp operation_result(:start, {:ok, worker, input, context}, data) do
    # Publish ownership before execution can call back into this server.
    active = %{data.active | worker: worker, worker_ref: Process.monitor(worker)}
    runner = data.runner
    id = active.worker_id
    policy = Core.execution_policy(data.exec_opts)

    case ServerSupervisor.remember_execution(data.activation_state, runner, id, worker) do
      :ok ->
        operation(:execute, %{data | active: active}, fn ->
          Runner.start_execution(runner, id, Jido.Exec.Fact.local_value(input),
            run_context: %{_global: context},
            scheduler_policies: [{:default, policy}]
          )
        end)

      error ->
        operation_result(:start, error, %{data | active: active})
    end
  end

  defp operation_result(:execute, {:ok, execution_id}, data),
    do: {:next_state, :running, put_in(data.active.execution_id, execution_id)}

  defp operation_result(:cleanup, :ok, data) do
    ServerSupervisor.forget_execution(data.activation_state)
    if data.active.worker_ref, do: Process.demonitor(data.active.worker_ref, [:flush])

    if data.active.durable,
      do:
        Jido.AgentServer.DurableTurn.CheckpointStore.unregister(data.jido, data.active.worker_id)

    data = data |> put_in([:active, :worker], nil) |> put_in([:active, :worker_ref], nil)

    cond do
      data.active.abort_reason -> finish(data, {:error, data.active.abort_reason})
      expired?(data.active) -> finish(data, {:error, :turn_timeout})
      true -> finish(data, data.active.result)
    end
  end

  defp operation_result(:cleanup, {:error, reason}, data),
    do:
      stop_failed(
        data,
        execution_error("Worker cleanup could not be confirmed", reason),
        :cleaning
      )

  defp operation_result(:save, result, data) do
    {timer, deadline} = data.active.storage
    Process.cancel_timer(timer)

    case Durable.write_result(result, deadline) do
      :ok -> publish_commit(data, data.active.result)
      {:error, reason} -> stop_durable(data, reason)
    end
  end

  defp operation_result(:reconfigure, :ok, data), do: finish(data, data.active.result)
  defp operation_result(:reconfigure, {:error, reason}, data), do: finish(data, {:error, reason})

  defp operation_result(:resume_plugins, :ok, data) do
    data = put_in(data.active.paused_plugins, [])
    finish_result(data, data.active.result)
  end

  defp operation_result(:resume_plugins, _, data),
    do:
      stop_failed(data, execution_error("Plugin resume failed", :plugin_resume_failed), :cleaning)

  defp operation_result(:reconcile, {:ok, refs, _members}, data) do
    Process.cancel_timer(data.active.effect_timer)
    replies = Enum.flat_map(data.ready_waiters, &reply(&1, :ok))
    data = %{data | plugin_refs: refs, ready_waiters: []}
    data = put_in(data.active.reconciling, false)
    data = put_in(data.active.paused_plugins, [])

    case begin_effects(data, data.active.effects) do
      {:next_state, phase, next, actions} -> {:next_state, phase, next, replies ++ actions}
    end
  end

  defp operation_result(:reconcile, _, data),
    do:
      stop_failed(
        data,
        execution_error("Committed composition is not ready", :composition_not_ready),
        :effects
      )

  defp operation_result(:policy, decision, data) do
    if System.monotonic_time(:millisecond) >= data.active.policy_deadline,
      do: complete_terminal(data, {:stop, :error_policy_timeout}),
      else: complete_terminal(data, decision)
  end

  defp operation_result(:commit_hook, result, data) do
    cond do
      System.monotonic_time(:millisecond) >= data.active.effect_deadline ->
        finish_effects(data, :timed_out)

      result != :ok ->
        finish_effects(data, :failed)

      true ->
        data = update_in(data.active.commit_hooks, &tl/1)

        data =
          if data.active.commit_hooks == [] do
            Process.cancel_timer(data.active.effect_timer)

            %{
              data
              | active: %{
                  data.active
                  | effect_deadline: System.monotonic_time(:millisecond) + data.directive_timeout,
                    effect_timer:
                      Process.send_after(
                        self(),
                        {:effect_timeout, data.active.turn_id},
                        data.directive_timeout
                      )
                }
            }
          else
            data
          end

        next_effect(data)
    end
  end

  defp operation_result(:effect, result, data) do
    case Effects.settle(data.active, result, System.monotonic_time(:millisecond)) do
      :timed_out ->
        finish_effects(data, :timed_out)

      {:stop, reason} ->
        Process.cancel_timer(data.active.effect_timer)

        data =
          data |> update_in([:active, :effect_index], &(&1 + 1)) |> record_effects(:succeeded)

        {:stop, normalize_stop_reason(reason), data}

      {:reported_error, error} ->
        Process.cancel_timer(data.active.effect_timer)
        data = record_effects(data, :failed)
        data = %{data | error_count: data.error_count + 1}
        apply_failure_policy(put_in(data.active.result, {:error, error}))

      {:reply, signal} ->
        ReplyGate.deliver(data.active.requester, signal)
        next_effect(update_in(data.active.effect_index, &(&1 + 1)))

      :continue ->
        next_effect(update_in(data.active.effect_index, &(&1 + 1)))

      :failed ->
        finish_effects(data, :failed)
    end
  end

  defp operation_result(:settle, {:error, stage, reason}, data),
    do: cleanup(put_in(data.active.failure_stage, stage), {:error, reason})

  defp operation_result(:settle, result, data), do: cleanup(data, result)

  defp operation_result(kind, {:error, reason}, data),
    do:
      cleanup(
        put_in(data.active.failure_stage, if(kind == :prepare, do: :preparing, else: :starting)),
        {:error, reason}
      )

  defp expired?(%{deadline: :infinity}), do: false
  defp expired?(active), do: System.monotonic_time(:millisecond) >= active.deadline

  defp abort_turn(phase, %{active: %{durable: true, durable_finalized: false}} = data, reason) do
    if data.active.operation, do: Task.shutdown(data.active.operation.task, :brutal_kill)
    if data.active.durable_storage, do: Process.cancel_timer(elem(data.active.durable_storage, 0))
    data = put_in(data.active.operation, nil)
    if data.active.wait_from, do: :gen_statem.reply(data.active.wait_from, {:error, reason})
    data = put_in(data.active.wait_from, nil)
    status = if reason == :cancelled, do: :cancelled, else: :failed
    receipt = %{data.server_turn | status: status}

    data =
      data
      |> Map.put(:server_turn, receipt)
      |> put_in([:active, :durable_next], {:abort, phase, reason})

    durable_write(:durable_terminal, data, data.agent, receipt)
  end

  defp abort_turn(:cleaning, data, reason) do
    data =
      if data.active.abort_reason, do: data, else: put_in(data.active.failure_stage, :cleaning)

    {:keep_state, put_in(data.active.abort_reason, data.active.abort_reason || reason)}
  end

  defp abort_turn(phase, data, reason) do
    # Stop the lifecycle task before checking for a Worker. A startup request
    # may already be in the local Worker supervisor mailbox.
    if data.active.operation, do: Task.shutdown(data.active.operation.task, :brutal_kill)
    data = put_in(data.active.operation, nil)
    data = put_in(data.active.failure_stage, phase)
    cleanup(put_in(data.active.abort_reason, reason), nil)
  end

  defp cleanup(data, result) do
    data = cancel_wait_timer(data)
    runner = data.runner
    id = data.active.worker_id
    worker = data.active.worker

    operation(:cleanup, put_in(data.active.result, result), fn ->
      # This local supervisor barrier waits for any start_child request sent
      # by the stopped startup task. No new startup task can follow it.
      DynamicSupervisor.which_children(Module.concat(runner, WorkerSupervisor))

      case Runner.lookup(runner, id) do
        nil when is_nil(worker) -> :ok
        nil -> {:error, :worker_lost_before_cleanup}
        _worker -> Runner.cancel(runner, id)
      end
    end)
  end

  defp start_worker(runner, id, owner, prepared, exec_opts) do
    with {:ok, instruction} <-
           Jido.Instruction.resolve(
             prepared.turn.executable,
             prepared.turn.input,
             prepared.context
           ),
         {:ok, input} <- execution_input(instruction),
         {:ok, workflow} <- Jido.Exec.compile(%{instruction | context: %{}}),
         :ok <- Jido.Exec.Node.Wait.validate_host(workflow),
         {:ok, worker} <-
           Runner.start_workflow(runner, id, workflow,
             owner: owner,
             max_concurrency: Keyword.get(exec_opts, :max_concurrency, 1),
             checkpoint_strategy: :manual,
             runnable_order: &execution_order/1,
             hooks: Core.execution_hooks(Keyword.get(exec_opts, :hooks, []), TraceContext.get()),
             on_complete: fn ^id, _workflow -> send(owner, {:worker_complete, id}) end
           ) do
      {:ok, worker, input, instruction.context}
    end
  end

  defp execution_input(%Jido.Instruction{kind: :action}), do: {:ok, %{}}

  defp execution_input(%Jido.Instruction{kind: :flow} = instruction) do
    with {:ok, params} <-
           Jido.Exec.Validation.input(instruction.target, instruction.params, %{
             phase: :flow_input
           }),
         do: {:ok, Jido.Exec.Frame.new(params)}
  end

  defp execution_order(runnable) do
    index =
      case Jido.Exec.Fact.value(runnable.input_fact) do
        {:jido_map_item, index, _id, _params} -> index
        _value -> 0
      end

    {elem(Runic.Workflow.Runnable.order_key(runnable), 0), Map.get(runnable.node, :name), index,
     Runic.Workflow.Runnable.activation_id(runnable)}
  end

  defp settle_worker(runner, active, config) do
    result =
      if active.durable do
        with {:ok, workflow} <- Runner.get_workflow(runner, active.worker_id),
             do: Jido.Exec.result(workflow)
      else
        with {:ok, observation} <- Runner.execution(runner, active.worker_id, active.execution_id),
             {:ok, workflow} <- Runner.get_workflow(runner, active.worker_id),
             do: Jido.Exec.result(workflow, observation)
      end

    case AgentRunner.finish_for_server(active.prepared, result) do
      {:error, _stage, reason} ->
        {:error, if(match?({:error, _}, result), do: :running, else: :settling), reason}

      {:ok, candidate, directives} ->
        with {:ok, candidate} <- Jido.Agent.Composition.bind(candidate),
             :ok <- CompositionRuntime.check(config, candidate, directives),
             :ok <- Effects.validate_batch(directives, %{config | agent: candidate}) do
          {:ok, candidate, directives}
        else
          {:error, reason} -> {:error, :directives, reason}
        end
    end
  end

  defp execution_error(message, reason),
    do: Jido.Error.execution_error(message, %{reason: reason})

  defp stop_policy(data) do
    if data.active.operation, do: Task.shutdown(data.active.operation.task, :brutal_kill)
    complete_terminal(data, {:stop, :error_policy_failed})
  end

  defp stop_failed(data, _error, :effects) do
    if data.active.operation, do: Task.shutdown(data.active.operation.task, :brutal_kill)
    data = record_effects(data, :indeterminate)
    {:stop, {:shutdown, :effect_lifecycle_failed}, %{data | active: nil}}
  end

  defp stop_failed(%{active: %{outcome: outcome}} = data, _error, :policy)
       when not is_nil(outcome),
       do: stop_policy(data)

  defp stop_failed(data, error, phase) do
    data =
      if data.active && is_nil(data.active.outcome),
        do: record_outcome(data, :indeterminate, phase, false, 0),
        else: data

    replies =
      if data.active,
        do:
          reply(data.active.from, {:error, error}) ++
            reply(data.active.wait_from, {:error, error}) ++
            cancel_replies(data.active, {:error, error}),
        else: []

    {:stop_and_reply, {:shutdown, :execution_lifecycle_failed}, replies, data}
  end

  defp postpone_turn(type, token, data, reply_gate \\ nil) do
    case Core.queue_decision(data.postponed, token, data.max_postponed_signals) do
      :duplicate ->
        {:keep_state_and_data, [:postpone]}

      {:overloaded, count} ->
        reject_turn(
          type,
          {:overloaded, %{limit: data.max_postponed_signals, postponed: count}},
          data,
          reply_gate
        )

      :accept ->
        next = %{
          data
          | postponed: MapSet.put(data.postponed, token),
            queued_from: Map.put(data.queued_from, token, type)
        }

        {:keep_state, next, [:postpone]}
    end
  end

  defp reject_turn(type, reason, data, reply_gate \\ nil) do
    ReplyGate.done(reply_gate)
    {:keep_state, data, turn_rejection(type, reason, data)}
  end

  defp turn_rejection(:cast, reason, data) do
    Logger.warning("AgentServer cast dropped", agent_id: data.agent.id, reason: reason)
    []
  end

  defp turn_rejection({:call, from}, reason, _data), do: reply(from, {:error, reason})

  defp identify_topology(%{persistence: persistence, agent: before}, candidate)
       when persistence not in [nil, false],
       do: TopologyRuntime.identify(before, candidate)

  defp identify_topology(_data, candidate), do: {:ok, candidate}

  defp finish(%{active: %{durable: true, durable_finalized: false}} = data, {:error, _} = result) do
    receipt = %{data.server_turn | status: :failed}

    data =
      data
      |> Map.put(:server_turn, receipt)
      |> put_in([:active, :durable_next], {:finish, result})

    durable_write(:durable_terminal, data, data.agent, receipt)
  end

  defp finish(%{active: active} = data, {:ok, candidate, directives})
       when not is_map_key(active, :configuration_checked) do
    case identify_topology(data, candidate) do
      {:ok, candidate} -> configure_commit(data, active, {:ok, candidate, directives})
      {:error, reason} -> finish(data, {:error, reason})
    end
  end

  defp finish(%{active: %{paused_plugins: [_ | _] = paused}} = data, {:error, _} = result) do
    data = put_in(data.active.result, result)

    operation(:resume_plugins, data, fn ->
      Plugin.pause(paused, data.plugin_refs, :resume)
    end)
  end

  defp finish(%{persistence: persistence} = data, {:ok, candidate, _} = result)
       when persistence not in [nil, false] do
    cancel_timer(data.active)
    deadline = System.monotonic_time(:millisecond) + data.persistence_timeout

    timer =
      Process.send_after(
        self(),
        {:persistence_timeout, data.active.turn_id},
        data.persistence_timeout
      )

    active = Map.merge(data.active, %{result: result, storage: {timer, deadline}})

    receipt =
      if data.active.durable, do: %{data.server_turn | status: :completed}, else: data.server_turn

    data = %{data | server_turn: receipt}

    operation(:save, %{data | active: active}, fn ->
      Durable.save(data, candidate, data.state_version + 1, data.state_version, receipt)
    end)
  end

  defp finish(data, {:ok, _, _} = result), do: publish_commit(data, result)
  defp finish(data, result), do: finish_result(data, result)

  defp configure_commit(data, active, {:ok, candidate, directives} = result) do
    changed = Jido.Agent.Mutation.changed_plugins(data.agent, candidate, directives)

    paused =
      Enum.filter(
        data.plugin_specs,
        &(&1.module in changed and match?(%{runtime?: true}, &1.agent_server))
      )

    active =
      Map.merge(active, %{
        configuration_checked: true,
        paused_plugins: paused,
        changed_plugins: changed,
        diff: Jido.Agent.Diff.between(data.agent, candidate),
        result: result
      })

    data = %{data | active: active}

    if paused == [],
      do: finish(data, result),
      else:
        operation(:reconfigure, data, fn ->
          Plugin.pause(paused, data.plugin_refs, :quiesce)
        end)
  end

  defp stop_durable(data, reason),
    do: stop_failed(data, execution_error("Required durable commit failed", reason), :saving)

  defp publish_commit(data, {:ok, candidate, _directives} = result) do
    case ServerSupervisor.publish_checkpoint(
           data.activation_state,
           candidate,
           data.state_version + 1
         ) do
      :ok ->
        finish_result(data, result)

      {:error, reason} ->
        stop_failed(data, execution_error("Local checkpoint failed", reason), :checkpoint)
    end
  end

  defp finish_result(data, result) do
    {next, status, stage, count} =
      case result do
        {:ok, candidate, directives} ->
          changed = data.active.changed_plugins

          {:ok, specs} =
            Jido.Plugin.Normalizer.normalize_all(Jido.Agent.runtime_plugins(candidate))

          active =
            Map.merge(data.active, %{
              changed_plugins: changed,
              composition_changed:
                TopologyRuntime.changed?(data.active.diff, data.agent, candidate),
              commit_plugins: Enum.reject(specs, &(&1.module in changed))
            })

          {%{
             data
             | agent: candidate,
               plugin_specs: specs,
               active: active,
               state_version: data.state_version + 1,
               error_count: 0
           }, :succeeded, :commit, length(directives)}

        {:error, reason} ->
          if is_nil(data.active.from),
            do:
              Logger.warning("AgentServer cast turn failed",
                agent_id: data.agent.id,
                turn_id: data.active.turn_id
              )

          status = Core.outcome_status(reason)
          errors = Core.next_error_count(status, data.error_count)
          {%{data | error_count: errors}, status, data.active.failure_stage || :cleaning, 0}
      end

    cancel_timer(data.active)

    next =
      next
      |> put_in([:active, :result], result)
      |> record_outcome(status, stage, status == :succeeded, count)

    case result do
      {:ok, _, directives} ->
        effects = Enum.reject(directives, &Jido.Agent.Mutation.mutation?/1)

        if next.active.composition_changed or next.active.changed_plugins != [] do
          begin_reconciliation(next, effects)
        else
          if effects != [] or Plugin.commit_specs(next.plugin_specs) != [],
            do: begin_effects(next, effects),
            else: complete_terminal(next, :continue)
        end

      {:error, _} when status == :failed ->
        apply_failure_policy(next)

      _ ->
        complete_terminal(next, :continue)
    end
  end

  defp begin_reconciliation(data, effects) do
    owner = self()
    replies = reply(data.active.from, data.active.result) ++ cancel_replies(data.active, :ok)

    active =
      Map.merge(data.active, %{
        from: nil,
        cancel_waiters: [],
        effects: effects,
        reconciling: true,
        effect_deadline: System.monotonic_time(:millisecond) + data.readiness_timeout,
        effect_timer:
          Process.send_after(
            self(),
            {:composition_timeout, data.active.turn_id},
            data.readiness_timeout
          )
      })

    data = %{data | active: active}
    runtime = Map.put(data, :owner, owner)

    {:next_state, phase, next} =
      operation(:reconcile, data, fn ->
        with {:ok, refs} <- Plugin.rebuild(runtime, owner, data.active.changed_plugins),
             {:ok, members} <- CompositionRuntime.reconcile(runtime),
             do: {:ok, refs, members}
      end)

    {:next_state, phase, next, replies}
  end

  defp begin_effects(data, directives) do
    active = data.active
    replies = reply(active.from, active.result) ++ cancel_replies(active, :ok)

    hooks = Plugin.commit_specs(Map.get(active, :commit_plugins, data.plugin_specs))
    timeout = if hooks == [], do: data.directive_timeout, else: data.commit_timeout
    timer_kind = if hooks == [], do: :effect_timeout, else: :commit_timeout

    active = %{
      active
      | from: nil,
        commit_hooks: hooks,
        cancel_waiters: [],
        effects: directives,
        effect_deadline: System.monotonic_time(:millisecond) + timeout,
        effect_timer: Process.send_after(self(), {timer_kind, active.turn_id}, timeout)
    }

    Semantic.point([:jido, :agent_server, :effects, :start], active.span.metadata, %{
      directive_count: length(directives)
    })

    {:next_state, :effects, %{data | active: active},
     replies ++ [{:next_event, :internal, :effect_next}]}
  end

  defp next_effect(data) do
    active = data.active

    next =
      case active.commit_hooks do
        [plugin | _] -> {:commit_hook, plugin}
        [] -> Effects.next(active, System.monotonic_time(:millisecond))
      end

    case next do
      :timed_out ->
        finish_effects(data, :timed_out)

      {:commit_hook, plugin} ->
        operation(:commit_hook, data, fn -> Plugin.after_commit(data, active, plugin) end)

      :done ->
        finish_effects(data, :succeeded)

      {:effect, directive} ->
        handler = data.directive_handler

        context = %{
          agent: data.agent,
          activation_state: data.activation_state,
          parent: data.parent,
          jido: data.jido,
          partition: data.partition,
          server: self(),
          turn_id: active.turn_id,
          signal_id: active.signal_id,
          state_version: data.state_version,
          default_dispatch: data.default_dispatch,
          plugin_specs: data.plugin_specs,
          plugin_refs: data.plugin_refs,
          source_signal: active.source_signal,
          effective_signal: active.prepared.signal,
          turn_context: active.turn_context,
          requester: active.requester
        }

        operation(:effect, data, fn ->
          case Plugin.dispatch(data, active, directive) do
            :unowned when is_function(handler, 2) ->
              Effects.run(directive, handler, context)

            :unowned ->
              if Jido.Agent.Directive.built_in?(directive),
                do: Effects.run(directive, nil, context),
                else: :ok

            result ->
              result
          end
        end)
    end
  end

  defp record_effects(data, status) do
    active = data.active
    outcome = Effects.outcome(active, data.state_version, status)

    Semantic.point(
      [:jido, :agent_server, :effects, :stop],
      Map.merge(active.span.metadata, %{
        committed?: true,
        stage: outcome.stage,
        status: telemetry_status(status)
      }),
      %{directive_completed: active.effect_index, directive_count: length(active.effects)}
    )

    data |> Map.put(:last_effect_outcome, outcome) |> put_in([:active, :effect_outcome], outcome)
  end

  defp finish_effects(data, status) do
    Process.cancel_timer(data.active.effect_timer)
    data = record_effects(data, status)
    ReplyGate.done(data.active.requester)
    TraceContext.clear()
    idle_transition(%{data | active: nil})
  end

  defp record_outcome(data, status, stage, committed, count) do
    active = data.active
    outcome = Core.outcome(active, data.state_version, status, stage, committed, count)

    metadata = %{
      status: telemetry_status(status),
      stage: if(committed, do: :commit, else: :evaluate),
      committed?: committed
    }

    measurements = %{
      state_version_before: active.start_version,
      state_version_after: data.state_version,
      directive_count: count
    }

    if committed do
      Semantic.point(
        [:jido, :agent_server, :commit],
        Map.merge(active.span.metadata, metadata),
        measurements
      )

      Semantic.point([:jido, :agent_server, :directives, :returned], active.span.metadata, %{
        directive_count: count
      })
    end

    Semantic.finish(active.span, metadata, measurements)

    Semantic.point(
      [:jido, :agent_server, :turn, :settled],
      Map.merge(active.span.metadata, metadata),
      measurements
    )

    history = Core.retain_history(data.history, outcome, data.debug, data.debug_max_events)

    data
    |> Map.merge(%{last_outcome: outcome, history: history})
    |> put_in([:active, :outcome], outcome)
  end

  defp telemetry_status(:succeeded), do: :ok
  defp telemetry_status(:failed), do: :error
  defp telemetry_status(status), do: status

  defp apply_failure_policy(data) do
    case Core.failure_decision(data.error_policy, data.error_count, data.active.signal_type) do
      {:complete, decision} -> complete_terminal(data, decision)
      :run -> run_failure_policy(data)
    end
  end

  defp run_failure_policy(data) do
    policy = data.error_policy
    active = data.active
    error = elem(active.result, 1)
    agent_id = data.agent.id
    jido = data.jido

    timer =
      Process.send_after(self(), {:policy_timeout, active.turn_id}, data.error_policy_timeout)

    data =
      data
      |> put_in([:active, :policy_timer], timer)
      |> put_in(
        [:active, :policy_deadline],
        System.monotonic_time(:millisecond) + data.error_policy_timeout
      )

    operation(:policy, data, fn ->
      summary =
        if active.effect_outcome,
          do: Map.merge(active.outcome, %{status: :failed, stage: :directive}),
          else: active.outcome

      try do
        case policy do
          {:emit_signal, target} ->
            Effects.report_error(summary, agent_id, active.signal_id, target, jido)

          fun ->
            fun.(error, summary)
        end
      rescue
        _ -> {:stop, :error_policy_failed}
      catch
        _, _ -> {:stop, :error_policy_failed}
      end
    end)
  end

  defp complete_terminal(data, decision) do
    if data.active.policy_timer, do: Process.cancel_timer(data.active.policy_timer)
    replies = reply(data.active.from, data.active.result) ++ cancel_replies(data.active, :ok)
    ReplyGate.done(data.active.requester)
    TraceContext.clear()
    next = %{data | active: nil}

    case decision do
      :continue ->
        idle_transition(next, replies)

      {:stop, reason} when is_atom(reason) ->
        {:stop_and_reply, {:shutdown, reason}, replies, next}

      _ ->
        {:stop_and_reply, {:shutdown, :invalid_error_policy_result}, replies, next}
    end
  end

  defp runtime_value(nil, _key, default), do: default

  defp runtime_value(table, key, default) do
    case :ets.lookup(table, key) do
      [{^key, value}] -> value
      [] -> default
    end
  end

  defp persist_runtime(nil, _key, _value), do: :ok
  defp persist_runtime(table, key, value), do: :ets.insert(table, {key, value})

  defp monitor_owners(table),
    do: Map.new(runtime_value(table, :owners, []), &{&1, Process.monitor(&1)})

  defp set_admission(data, mode) do
    persist_runtime(data.activation_state, :admission, mode)
    %{data | admission_mode: mode}
  end

  defp control_caller?(from, data) do
    {caller, _} = from

    Core.reentrant?({:call, from}, data) or Core.bootstrap_caller?(from, data) or
      Enum.any?([data.parent_effect, data.control], fn operation ->
        operation != nil and operation.task != nil and
          Core.owned_process?(caller, operation.task.pid, [], 0)
      end)
  end

  defp settled?(data),
    do: data.active == nil and data.parent_effect == nil and MapSet.size(data.postponed) == 0

  defp begin_control(phase, data, kind, from, policy, timeout) do
    token = make_ref()

    control = %{
      kind: kind,
      from: from,
      prior: data.admission_mode,
      token: token,
      timer: Process.send_after(self(), {:control_timeout, token}, timeout),
      deadline: System.monotonic_time(:millisecond) + timeout,
      task: nil
    }

    data = data |> cancel_idle() |> set_admission(:quiescing) |> Map.put(:control, control)

    replies =
      Enum.flat_map(data.queued_from, fn {_token, type} ->
        turn_rejection(type, :quiesced, data)
      end)

    data = %{data | queued_from: %{}}
    progress = replies ++ [{:next_event, :internal, :control_progress}]

    if policy == :cancel and data.active != nil and phase not in [:saving, :policy, :effects] do
      case abort_turn(phase, data, :cancelled) do
        {:next_state, next_phase, next} -> {:next_state, next_phase, next, progress}
        {:keep_state, next} -> {:keep_state, next, progress}
      end
    else
      # Reject waiting callers now. OTP drains their postponed events on the
      # next phase change; resume waits for that drain before opening admission.
      {:keep_state, data, progress}
    end
  end

  defp control_progress(data) do
    cond do
      data.control != nil and System.monotonic_time(:millisecond) >= data.control.deadline ->
        control_timeout(data)

      data.admission_mode == :quiescing and
          (settled?(data) or suspended_hibernation?(data)) ->
        case data.control do
          nil ->
            {:keep_state, set_admission(data, :quiesced)}

          %{kind: :quiesce} = control ->
            Process.cancel_timer(control.timer)

            {:keep_state, data |> set_admission(:quiesced) |> Map.put(:control, nil),
             reply(control.from, :ok)}

          %{task: nil} ->
            # Recovery must not reopen an interrupted writer. Keep this marker
            # before starting storage, including the write-before-reply window.
            persist_runtime(data.activation_state, :admission, :blocked)

            deadline =
              min(
                data.control.deadline,
                System.monotonic_time(:millisecond) + data.persistence_timeout
              )

            Process.cancel_timer(data.control.timer)

            timer =
              Process.send_after(
                self(),
                {:control_timeout, data.control.token},
                remaining_wait(deadline)
              )

            task =
              Task.async(fn ->
                Durable.save(
                  data,
                  data.agent,
                  data.state_version,
                  data.state_version,
                  data.server_turn
                )
              end)

            next = %{
              data
              | control: %{data.control | task: task, timer: timer, deadline: deadline}
            }

            if suspended_hibernation?(data),
              do: {:next_state, :hibernating, cancel_wait_timer(next)},
              else: {:keep_state, next}

          _ ->
            :keep_state_and_data
        end

      true ->
        :keep_state_and_data
    end
  end

  defp control_timeout(data) do
    if data.control.task do
      Task.shutdown(data.control.task, :brutal_kill)
      control_failed(data, :indeterminate, false)
    else
      result =
        if data.control.kind == :hibernate,
          do: Durable.error(:quiesce_timeout, true),
          else: {:error, :quiesce_timeout}

      replies = reply(data.control.from, result)

      {:keep_state, %{data | control: nil},
       replies ++ [{:next_event, :internal, :control_progress}]}
    end
  end

  defp control_failed(data, reason, safe?) do
    control = data.control
    Process.cancel_timer(control.timer)
    mode = if safe?, do: if(control.prior == :open, do: :open, else: :quiesced), else: :blocked
    # A failed idle save closes admission. Do not start an automatic retry loop.
    mode = if control.from == nil and mode == :open, do: :quiesced, else: mode
    data = data |> set_admission(mode) |> Map.put(:control, nil) |> arm_idle()

    if data.active && data.active.waits != [] do
      if safe? and expired?(data.active), do: send(self(), {:turn_timeout, data.active.turn_id})

      {:next_state, :waiting, arm_wait_timer(data),
       reply(control.from, Durable.error(reason, safe?))}
    else
      {:keep_state, data, reply(control.from, Durable.error(reason, safe?))}
    end
  end

  defp idle_transition(data, replies \\ []) do
    {:next_state, :idle, arm_idle(data),
     replies ++
       [{:next_event, :internal, :recover_turn}, {:next_event, :internal, :control_progress}]}
  end

  defp cancel_idle(%{idle_timer: nil} = data), do: data

  defp cancel_idle(data) do
    {timer, _} = data.idle_timer
    Process.cancel_timer(timer)
    %{data | idle_timer: nil}
  end

  defp arm_idle(data) do
    data = cancel_idle(data)

    if data.idle_timeout != :infinity and data.admission_mode == :open and
         map_size(data.owners) == 0 and settled?(data) do
      token = make_ref()
      timer = Process.send_after(self(), {:idle_timeout, token}, data.idle_timeout)
      %{data | idle_timer: {timer, token}}
    else
      data
    end
  end

  defp cancel_timer(%{timer: nil}), do: :ok
  defp cancel_timer(active), do: Process.cancel_timer(active.timer)

  defp cancel_replies(active, result),
    do: Enum.flat_map(active.cancel_waiters, &reply(&1, result))

  defp reply(nil, _result), do: []
  defp reply(from, result), do: [{:reply, from, result}]

  defp wait_for_input(data, waits, deadline) do
    data =
      data
      |> put_in([:active, :waits], waits)
      |> put_in([:active, :wait_deadline], deadline)
      |> put_in([:active, :advance_pending], false)
      |> arm_wait_timer()

    {:next_state, :waiting, data, [{:next_event, :internal, :control_progress}]}
  end

  defp suspended_hibernation?(%{
         control: %{kind: :hibernate},
         active: %{worker: nil, operation: nil, waits: [_ | _]}
       }),
       do: true

  defp suspended_hibernation?(_data), do: false

  defp cancel_wait_timer(%{active: nil} = data), do: data

  defp cancel_wait_timer(data) do
    if data.active.wait_timer, do: Process.cancel_timer(data.active.wait_timer)
    data |> put_in([:active, :wait_timer], nil) |> put_in([:active, :wait_token], nil)
  end

  defp arm_wait_timer(%{active: %{wait_deadline: deadline}} = data) when is_integer(deadline) do
    data = cancel_wait_timer(data)
    token = make_ref()
    delay = min(Core.max_timeout(), max(0, deadline - System.system_time(:millisecond)))
    timer = Process.send_after(self(), {:wait_wake, data.active.turn_id, token}, delay)
    data |> put_in([:active, :wait_timer], timer) |> put_in([:active, :wait_token], token)
  end

  defp arm_wait_timer(data), do: data

  defp complete_task(task) do
    Process.demonitor(task.ref, [:flush])
    Process.unlink(task.pid)
    :ok
  end
end
