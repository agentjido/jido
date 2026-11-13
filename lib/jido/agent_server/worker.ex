defmodule Jido.AgentServer.Worker do
  @moduledoc false

  @behaviour :gen_statem

  @typedoc "A local AgentServer PID or registered OTP server name."
  @type server :: :gen_statem.server_ref()

  @type signal_result :: {:ok, Jido.AgentServer.TurnResult.t()} | {:error, term()}

  require Logger

  alias Jido.Agent
  alias Jido.AgentOwnership
  alias Jido.Agent.Directive.Reply

  alias Jido.AgentServer.{
    Lifecycle,
    Effects,
    Pending,
    Plugin,
    RegistrationGuard,
    ReplyGate,
    Snapshot,
    Status,
    Topology
  }

  alias Jido.AgentServer.Supervisor, as: ServerSupervisor
  alias Jido.AgentServer.Command
  alias Jido.AgentServer.Plugin.Callbacks, as: PluginCallbacks
  alias Jido.Agent.Runner, as: AgentRunner
  alias Jido.Agent.Validation
  alias Jido.Durable.Continuation
  alias Jido.Persistence.ContinuationStore
  alias Jido.Signal
  alias Jido.Telemetry.AgentServer, as: AgentServerTelemetry
  alias Jido.Trace.Context, as: TraceContext
  alias Runic.Runner

  @type pending :: Pending.t()

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
      with {:ok, opts} <- activation_options(opts) do
        case ServerSupervisor.start_activation(
               Jido.Instance.Names.agent_supervisor(opts[:jido]),
               child_spec(opts)
             ) do
          {:error, {:shutdown, {:failed_to_start_child, __MODULE__, {:already_started, pid}}}} ->
            {:error, {:already_started, pid}}

          {:error, {:bad_return, {Jido.AgentServer.Supervisor, :init, {:stop, {:already_started, pid}}}}} ->
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
         true <- Lifecycle.unique_keyword?(opts) and Keyword.keys(opts) -- [:partition] == [],
         true <- valid_partition?(opts[:partition]),
         [{root, {:activation, _activation_id}}] <-
           Registry.lookup(
             Jido.Instance.Names.registry(jido),
             RegistrationGuard.registry_key(id, opts[:partition])
           ),
         pid when is_pid(pid) <- ServerSupervisor.live_worker(root),
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
           Jido.Plugin.Normalizer.normalize_runtime(
             Jido.Agent.Plugin.declarations(opts[:agent]),
             opts[:plugin_runtime_options]
           ) do
      if not Jido.Agent.Topology.empty?(opts[:agent].topology) or
           Topology.buses(opts[:agent]) != [] or
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
           {:ok, agent} <- validate_start_agent(opts),
           {:ok, _specs} <-
             Jido.Plugin.Normalizer.normalize_runtime(
               Jido.Agent.Plugin.declarations(agent),
               opts[:plugin_runtime_options]
             ),
           do: {:ok, Keyword.put(opts, :agent, agent)}
    else
      invalid_options("options must be a keyword list")
    end
  end

  def activation_options(_), do: invalid_options("options must be a keyword list")

  defp validate_start_agent(opts) do
    agent = Keyword.fetch!(opts, :agent)

    if opts[:persistence_mode] == :restore and match?(%Agent{state: nil}, agent) do
      with {:ok, _} <- Jido.Agent.Validation.validate_definition(Agent.definition(agent)),
           do: {:ok, agent}
    else
      Jido.Agent.Validation.validate_instance(agent)
    end
  end

  @doc false
  def start_worker(opts, activation) do
    initial = {Keyword.fetch!(opts, :agent), Keyword.put(opts, :activation, activation)}

    case Keyword.get(opts, :name) do
      nil -> :gen_statem.start_link(__MODULE__, initial, [])
      name when is_atom(name) -> :gen_statem.start_link({:local, name}, __MODULE__, initial, [])
      name -> :gen_statem.start_link(name, __MODULE__, initial, [])
    end
  end

  defp runtime_options(opts) do
    with true <- Lifecycle.unique_keyword?(opts),
         {:ok, opts} <- instance_options(opts),
         {:ok, opts} <- Lifecycle.with_turn_timeout(opts) do
      {:ok, Keyword.merge(Lifecycle.runtime_defaults(), opts)}
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
             runner = Jido.Instance.Names.exec_runner(jido),
             true <- Keyword.get(opts, :runner, runner) == runner,
             true <- valid_partition?(opts[:partition]) do
          defaults = Jido.Instance.RuntimeStore.instance_agent_server_options(jido)

          merged =
            defaults
            |> Keyword.merge(opts)
            |> Keyword.put(:idle_timeout, Keyword.fetch!(defaults, :idle_timeout))
            |> Keyword.put(:idle_policy, Keyword.fetch!(defaults, :idle_policy))
            |> Keyword.put(:runner, runner)

          {:ok, merged}
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
        Jido.Instance.Names.registry(jido),
        Jido.Instance.Names.agent_supervisor(jido),
        Jido.Instance.Names.registration_guard(jido)
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
    if Lifecycle.unique_keyword?(opts) and Keyword.keys(opts) -- Lifecycle.runtime_keys() == [] do
      validate_runtime(Keyword.merge(Lifecycle.runtime_defaults(), opts))
    else
      invalid_options("invalid instance AgentServer defaults")
    end
  end

  defp validate_options(opts) do
    name = Keyword.get(opts, :name)

    cond do
      Keyword.keys(opts) -- Lifecycle.startup_keys() != [] ->
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
        with :ok <- validate_activation_scope(opts),
             :ok <- validate_runner(Keyword.fetch!(opts, :runner), opts[:jido]),
             do: validate_runtime(opts)
    end
  end

  defp validate_runtime(opts) do
    with :ok <- Lifecycle.validate_runtime(opts),
         :ok <- Lifecycle.validate_timeout(opts, :directive_timeout),
         :ok <- Lifecycle.validate_timeout(opts, :readiness_timeout),
         :ok <- Lifecycle.validate_timeout(opts, :commit_timeout),
         :ok <- Lifecycle.validate_timeout(opts, :idle_timeout, false),
         :ok <- Lifecycle.validate_setting(opts[:idle_policy] in [:stop, :hibernate], :idle_policy),
         :ok <- Lifecycle.validate_limit(opts, :max_directives_per_turn),
         :ok <-
           Lifecycle.validate_setting(
             Effects.validate_dispatch(opts[:default_dispatch]) == :ok,
             :default_dispatch
           ),
         do: :ok
  end

  defp validate_activation_scope(opts) do
    if opts[:persistence] not in [nil, false] and is_nil(opts[:jido]),
      do: invalid_options("persistence requires a Jido instance with a stable namespace"),
      else: :ok
  end

  defp validate_runner(runner, _jido) do
    with pid when is_pid(pid) <- Process.whereis(runner),
         {:supervisor, Runner, 1} <- :proc_lib.translate_initial_call(pid),
         true <- live_runner_children?(runner, pid),
         {store, _state} <- Runner.get_store(runner),
         true <-
           store == Jido.Persistence.ContinuationStore do
      :ok
    else
      _other ->
        invalid_options("Runner must use Jido.Persistence.ContinuationStore")
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

  defp invalid_options(message), do: Lifecycle.invalid_options(message)

  @doc false
  @spec stop(server(), term(), timeout()) :: {:ok, Snapshot.t()} | {:error, term()}
  def stop(server, reason \\ :shutdown, timeout \\ 5_000) do
    with {:ok, _status} <- quiesce(server, active: :finish, timeout: timeout),
         %Snapshot{} = snapshot <- snapshot(server, timeout),
         :ok <- stop_activation(server, reason, timeout) do
      {:ok, snapshot}
    end
  end

  defp stop_activation(server, reason, timeout) do
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
  Cancels only the active turn with this ID. A different active ID returns
  `{:error, :stale_turn}`. An idle server returns `{:error, :not_running}`.
  Successful cancellation confirms cleanup, as with `cancel/2`.
  """
  @spec cancel_turn(server(), String.t(), timeout()) :: :ok | {:error, term()}
  def cancel_turn(server, turn_id, timeout \\ 5_000) when is_binary(turn_id),
    do: cancel_request(server, turn_id, timeout)

  defp cancel_request(server, id, timeout) do
    with :ok <- Lifecycle.validate_wait(timeout), do: :gen_statem.call(server, {:cancel, id}, timeout)
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
  @spec quiesce(server(), keyword()) :: {:ok, Status.t()} | {:error, term()}
  def quiesce(server, opts \\ []), do: control_request(server, :quiesce, opts)

  @doc "Opens admission after quiescence. An uncertain hibernation save forbids resume."
  @spec resume(server(), timeout()) :: {:ok, Status.t()} | {:error, term()}
  def resume(server, timeout \\ 5_000) do
    with :ok <- Lifecycle.validate_wait(timeout), do: :gen_statem.call(server, :resume, timeout)
  end

  defp control_request(server, kind, opts) do
    with {:ok, active, timeout} <- Lifecycle.control_options(opts) do
      # Allow the server to report its control deadline. The caller still has
      # a finite OTP wait if delivery or the server itself cannot progress.
      wait = Lifecycle.control_wait(timeout)

      :gen_statem.call(
        server,
        {:control, kind, active, timeout},
        wait
      )
    end
  end

  @doc "Returns one committed Plugin-owned state field."
  @spec plugin_state(server(), module(), timeout()) :: {:ok, term()} | {:error, term()}
  def plugin_state(server, plugin, timeout \\ 5_000) do
    with :ok <- Lifecycle.validate_wait(timeout),
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

    with {:ok, signal} <- Validation.normalize_signal(signal),
         {:ok, context} <- Lifecycle.turn_context(opts, [:timeout, :admission_timeout, :context]),
         timeout = Keyword.get(opts, :timeout, 5_000),
         :ok <- Lifecycle.validate_wait(timeout),
         {:ok, deadline} <- Lifecycle.admission_deadline(opts) do
      reply_gate = ReplyGate.start(self(), server)
      turn_id = Jido.Id.uuid7()

      try do
        result =
          :gen_statem.call(
            server,
            turn_event(turn_id, signal, context, deadline, reply_gate),
            timeout
          )

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
    with {:ok, signal} <- Validation.normalize_signal(signal),
         {:ok, context} <- Lifecycle.turn_context(opts, [:context, :admission_timeout]),
         {:ok, deadline} <- Lifecycle.admission_deadline(opts) do
      reply_gate = ReplyGate.start(self(), server)
      turn_id = Jido.Id.uuid7()
      public_request_id = Jido.Id.uuid7()

      request_id =
        :gen_statem.send_request(
          server,
          turn_event(turn_id, signal, context, deadline, reply_gate)
        )

      Process.put(
        {Pending, public_request_id},
        %{request_id: request_id, reply_gate: reply_gate}
      )

      %Pending{
        turn_id: turn_id,
        request_id: public_request_id
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
    with {:ok, signal} <- Validation.normalize_signal(signal),
         {:ok, context} <- Lifecycle.turn_context(opts, [:context]) do
      :gen_statem.cast(server, turn_event(Jido.Id.uuid7(), signal, context, :infinity, nil))
    end
  end

  defp turn_event(turn_id, signal, context, deadline, reply_gate),
    do: {:turn, turn_id, signal, context, deadline, reply_gate}

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

  def await(%Pending{request_id: public_request_id}, timeout) do
    with :ok <- Lifecycle.validate_wait(timeout),
         %{request_id: request_id, reply_gate: reply_gate} <-
           Process.get({Pending, public_request_id}) do
      case :gen_statem.wait_response(request_id, timeout) do
        {:reply, result} ->
          Process.delete({Pending, public_request_id})
          ReplyGate.open(reply_gate)
          result

        :timeout ->
          {:error, :timeout}

        {:error, {reason, _server}} ->
          Process.delete({Pending, public_request_id})
          ReplyGate.abandon(reply_gate)

          {:error,
           Jido.Error.execution_error("Agent server stopped before the turn replied", %{
             reason: reason
           })}
      end
    else
      nil -> invalid_options("await must run once in the process that submitted the turn")
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Discards a pending reply and releases its OTP request monitor. This does not
  cancel the submitted turn. Only the submitting process can abandon a handle.
  Discards an already queued reply too. Do not await this handle again.
  """
  @spec abandon(pending()) :: :ok | {:error, term()}
  def abandon(%Pending{request_id: public_request_id}) do
    case Process.delete({Pending, public_request_id}) do
      %{request_id: request_id, reply_gate: reply_gate} ->
        ReplyGate.abandon(reply_gate)
        _response = :gen_statem.receive_response(request_id, 0)
        :ok

      nil ->
        invalid_options("abandon must run once in the process that submitted the turn")
    end
  end

  @doc "Returns phase, identity, revision, queue counts, and a bounded active turn view."
  @spec status(server(), timeout()) :: Status.t() | {:error, term()}
  def status(server, timeout \\ 5_000) do
    with :ok <- Lifecycle.validate_wait(timeout), do: :gen_statem.call(server, :status, timeout)
  end

  @doc false
  @spec ownership(server(), timeout()) :: {:ok, AgentOwnership.t() | nil} | {:error, term()}
  def ownership(server, timeout) do
    with :ok <- Lifecycle.validate_wait(timeout),
         do: safe_runtime_call(server, :ownership, timeout)
  end

  @doc false
  @spec ownership_context(server(), timeout()) :: {:ok, map()} | {:error, term()}
  def ownership_context(server, timeout) do
    with :ok <- Lifecycle.validate_wait(timeout),
         do: safe_runtime_call(server, :ownership_context, timeout)
  end

  @doc false
  @spec transfer_ownership(server(), map(), AgentOwnership.t() | nil, String.t(), timeout()) ::
          {:ok, AgentOwnership.t()} | {:error, term()}
  def transfer_ownership(server, owner, expected, request_id, timeout) do
    with :ok <- Lifecycle.validate_wait(timeout),
         do: safe_runtime_call(server, {:transfer_ownership, owner, expected, request_id}, timeout)
  end

  defp safe_runtime_call(server, request, timeout) do
    try do
      :gen_statem.call(server, request, timeout)
    catch
      :exit, _reason -> {:error, :unavailable}
    end
  end

  @doc """
  Waits for Plugin startup and readiness. Caller timeout does not stop startup.

  Returns `{:error, reason}` when the worker failed to start, for example
  `:not_found`, `:conflict`, or `:deleted`, and `{:error, :timeout}` when the
  wait ends first. `{:error, :noproc}` means the process is gone and no start
  failure is recorded for it.
  """
  @spec await_ready(server(), timeout()) :: :ok | {:error, term()}
  def await_ready(server, timeout \\ 5_000) do
    with :ok <- Lifecycle.validate_wait(timeout) do
      try do
        :gen_statem.call(server, :await_ready, timeout)
      catch
        :exit, reason -> Lifecycle.ready_exit(server, reason)
      end
    end
  end

  @impl true
  def callback_mode, do: :handle_event_function

  @impl true
  def init({agent, opts}) do
    Process.flag(:trap_exit, true)
    Process.set_label({Jido.AgentServer, agent.id})
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
        registry = Jido.Instance.Names.registry(jido)
        key = RegistrationGuard.registry_key(id, opts[:partition])

        with [{root, {:activation, activation_id}}] <- Registry.lookup(registry, key),
             true <- root == opts[:activation],
             true <- activation_id == opts[:activation_id] do
          {:ok,
           Map.new(
             [jido, registry, Jido.Instance.Names.registration_guard(jido)],
             fn name -> {Process.monitor(Process.whereis(name)), name} end
           )}
        end
    end
  catch
    :exit, _ -> {:error, :instance_unavailable}
  end

  defp init_registered(agent, runner, opts, monitors) do
    AgentServerTelemetry.lifecycle(:start, agent.id)

    {:ok, specs} =
      Jido.Plugin.Normalizer.normalize_runtime(
        Jido.Agent.Plugin.declarations(agent),
        opts[:plugin_runtime_options]
      )

    data =
      Map.merge(Map.new(Lifecycle.runtime_keys(), &{&1, Keyword.fetch!(opts, &1)}), %{
        agent: agent,
        agent_address: agent_address(agent, opts),
        agent_activation_id: Keyword.fetch!(opts, :activation_id),
        agent_revision: Keyword.get(opts, :agent_revision, Keyword.get(opts, :state_version, 0)),
        persistence_revision:
          if(opts[:persistence] in [nil, false],
            do: nil,
            else: Keyword.get(opts, :state_version, 0)
          ),
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
        pending_handoff: nil,
        postponed: MapSet.new(),
        queued_from: %{},
        admission_mode: runtime_value(opts[:activation_state], :admission, :open),
        control: nil,
        idle_timer: nil,
        last_outcome: nil
      })

    if data.persistence not in [nil, false] do
      mode = Lifecycle.persistence_mode(data.activation_state, data.persistence_mode)
      bootstrap(data, :persistence, data.persistence_timeout, fn -> Lifecycle.start(data, mode) end)
    else
      initialize_plugins(data)
    end
  end

  defp agent_address(agent, opts) do
    namespace =
      case opts[:jido] do
        nil -> "jido.local"
        jido -> Jido.Instance.NamespaceRegistry.namespace(jido) || "jido.local"
      end

    Jido.Agent.Address.new!(namespace: namespace, partition: opts[:partition], id: agent.id)
  end

  defp initialize_plugins(data) do
    case Jido.Agent.Topology.bind(data.agent, data.agent.state, &Jido.Agent.Validation.resolve/2) do
      {:ok, _members} ->
        agent = data.agent

        {:ok, specs} =
          Jido.Plugin.Normalizer.normalize_runtime(
            Jido.Agent.Plugin.declarations(agent),
            data.plugin_runtime_options
          )

        if data.activation_state,
          do:
            Lifecycle.restore(
              data.activation_state,
              agent,
              data.state_version,
              data.agent_revision
            )

        initialize_bound_plugins(%{data | agent: agent, plugin_specs: specs})

      {:error, reason} ->
        {:stop, reason}
    end
  end

  defp initialize_bound_plugins(data) do
    if not Jido.Agent.Topology.empty?(data.agent.topology) or
         Topology.buses(data.agent) != [] or
         ServerSupervisor.execution(data.activation_state) != nil or
         Enum.any?(data.plugin_specs, &match?(%{agent_server: %{runtime?: true}}, &1)) do
      owner = self()

      bootstrap(data, :plugins, data.readiness_timeout, fn ->
        runtime = Map.put(data, :owner, owner)

        with :ok <- ServerSupervisor.close_execution(data.activation_state),
             :ok <- Topology.validate(runtime.agent),
             {:ok, refs} <- Plugin.bootstrap(data, owner),
             {:ok, _} <- Topology.reconcile(runtime),
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

  defp mark_ready(_data), do: :ok

  @doc "Returns one committed Agent and revision from the same server event."
  @spec snapshot(server(), timeout()) :: Snapshot.t() | {:error, term()}
  def snapshot(server, timeout \\ 5_000) do
    with :ok <- Lifecycle.validate_wait(timeout), do: :gen_statem.call(server, :snapshot, timeout)
  end

  defp monitor_parent(nil), do: nil

  defp monitor_parent(state) do
    case ServerSupervisor.parent(state) do
      nil -> nil
      parent -> Map.put(parent, :monitor, Process.monitor(parent.activation))
    end
  end

  defp change_ownership(%{parent: parent} = data, owner, expected, request_id) do
    request = %{expected: expected, owner_address: owner.address, request_id: request_id}

    cond do
      not is_nil(parent) and not match?(%{kind: :dynamic_ownership}, parent) ->
        {:error, :ownership_not_transferable}

      data.parent_effect != nil ->
        {:error, :ownership_transition_pending}

      idempotent_ownership_request?(parent, request) ->
        {:ok, public_ownership(data.agent_address, parent), data}

      conflicting_ownership_request?(parent, request_id) ->
        {:error, :request_id_conflict}

      public_ownership(data.agent_address, parent) != expected ->
        {:error, :stale_ownership}

      not Process.alive?(owner.activation) ->
        {:error, :owner_unavailable}

      match?(%{activation: activation} when activation == owner.activation, parent) ->
        {:error, :same_owner}

      true ->
        install_ownership(data, owner, request)
    end
  end

  defp idempotent_ownership_request?(%{kind: :dynamic_ownership, last_request: request}, request),
    do: true

  defp idempotent_ownership_request?(_parent, _request), do: false

  defp conflicting_ownership_request?(%{kind: :dynamic_ownership, request_id: request_id}, request_id),
    do: true

  defp conflicting_ownership_request?(_parent, _request_id), do: false

  defp install_ownership(data, owner, request) do
    sequence = ownership_sequence(data.activation_state) + 1
    fence = data.agent_activation_id <> ":" <> Integer.to_string(sequence)

    stored = %{
      kind: :dynamic_ownership,
      activation: owner.activation,
      agent_id: owner.address.id,
      address: owner.address,
      policy: :stop,
      dispatch: nil,
      jido: owner.jido,
      partition: owner.partition,
      fence: fence,
      request_id: request.request_id,
      last_request: request
    }

    monitor = Process.monitor(owner.activation)

    try do
      true =
        :ets.insert(data.activation_state, [
          {:parent, stored},
          {:ownership_sequence, sequence}
        ])

      release_parent_monitor(data.parent)
      parent = Map.put(stored, :monitor, monitor)
      ownership = public_ownership(data.agent_address, parent)
      {:ok, ownership, %{data | parent: parent}}
    rescue
      ArgumentError ->
        Process.demonitor(monitor, [:flush])
        {:error, :ownership_unavailable}
    end
  end

  defp ownership_sequence(state) do
    case :ets.lookup(state, :ownership_sequence) do
      [{:ownership_sequence, sequence}] when is_integer(sequence) and sequence >= 0 -> sequence
      _other -> 0
    end
  end

  defp release_parent_monitor(%{monitor: monitor}) when is_reference(monitor),
    do: Process.demonitor(monitor, [:flush])

  defp release_parent_monitor(_parent), do: true

  defp public_ownership(_agent_address, nil), do: nil

  defp public_ownership(agent_address, %{kind: :dynamic_ownership} = parent) do
    %AgentOwnership{
      agent_address: agent_address,
      owner_address: parent.address,
      fence: parent.fence,
      request_id: parent.request_id
    }
  end

  defp public_ownership(_agent_address, _parent), do: :not_transferable

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
    Map.new(ServerSupervisor.records(state), fn {{:child, tag}, record} ->
      {kind, pid} =
        case record do
          %{root: root} -> {:root, root}
          %{caller: caller} -> {:reservation, caller}
        end

      {Process.monitor(pid), {kind, tag, record.token}}
    end)
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
        Enum.map(Lifecycle.runtime_keys(), &{&1, Map.fetch!(data, &1)}) ++
          [runner: data.runner, jido: data.jido, partition: data.partition]
    }

    {:keep_state_and_data, reply(from, context)}
  end

  def handle_event({:call, from}, {:reserve_child, tag, token}, _phase, data) do
    {caller, _} = from
    result = ServerSupervisor.reserve(data.activation_state, tag, token, caller)

    data =
      if result == :ok,
        do: %{
          data
          | child_monitors: Map.put(data.child_monitors, Process.monitor(caller), {:reservation, tag, token})
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
        {:keep_state_and_data, reply(from, Lifecycle.error(:persistence_not_configured, true))}

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

    if result == :ok do
      data = data |> set_admission(:open) |> arm_idle()
      {:keep_state, data, reply(from, {:ok, public_status(phase, data)})}
    else
      {:keep_state_and_data, reply(from, result)}
    end
  end

  def handle_event(:internal, :control_progress, _phase, data), do: control_progress(data)

  def handle_event(:info, {:control_timeout, token}, _phase, %{control: %{token: token}} = data) do
    control_timeout(data)
  end

  def handle_event(:info, {ref, result}, _phase, %{control: %{task: %{ref: ref}}} = data) do
    complete_task(data.control.task)

    case Lifecycle.write_result(result, data.control.deadline) do
      :ok ->
        Process.cancel_timer(data.control.timer)
        # The caller installs its monitor before requesting save. Reply only
        # after save; it confirms the activation DOWN before returning success.
        replies = reply(data.control.from, :saved)
        {:stop_and_reply, {:shutdown, :hibernate}, replies, %{data | control: nil}}

      {:error, reason} ->
        control_failed(data, reason, Lifecycle.resumable?(reason))
    end
  end

  def handle_event(
        :info,
        {:DOWN, ref, :process, _, _},
        _phase,
        %{control: %{task: %{ref: ref}}} = data
      ),
      do: control_failed(data, :indeterminate, false)

  def handle_event(:info, {:idle_timeout, token}, :idle, %{idle_timer: {_, token}} = data) do
    data = %{data | idle_timer: nil}

    if data.admission_mode == :open and settled?(data) do
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

  def handle_event(
        :info,
        {:idle_timeout, token},
        :waiting,
        %{idle_timer: {_, token}, active: %{worker: nil, operation: nil, waits: [_ | _]}} = data
      ) do
    data = %{data | idle_timer: nil}

    if data.admission_mode == :open and safe_residency_idle?(data) do
      begin_control(:waiting, data, :hibernate, nil, :finish, data.persistence_timeout)
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
    do: {:keep_state_and_data, reply(from, Snapshot.new(data))}

  def handle_event(:cast, {kind, _source, _signal}, phase, _data)
      when kind in [:topology_output, :topology_bus] and
             phase in [:initializing, :restoring],
      do: {:keep_state_and_data, [:postpone]}

  def handle_event(:cast, {:topology_output, tag, signal}, _phase, data) do
    case Topology.member_output(Map.put(data, :server, self()), tag, signal) do
      :ok -> :keep_state_and_data
      {:error, reason} -> {:keep_state, topology_delivery_failed(data, signal, reason)}
    end
  end

  def handle_event(:cast, {:topology_bus, name, signal}, _phase, data) do
    case Topology.output(Map.put(data, :server, self()), %{kind: :bus, name: name}, signal) do
      :ok -> :keep_state_and_data
      {:error, reason} -> {:keep_state, topology_delivery_failed(data, signal, reason)}
    end
  end

  def handle_event({:call, from}, :await_ready, phase, data)
      when phase in [:restoring, :initializing] do
    {caller, _} = from

    if Lifecycle.owned_process?(caller, data.bootstrap.task.pid, [], 0) do
      {:keep_state_and_data, reply(from, {:error, :reentrant_turn})}
    else
      {:keep_state, %{data | ready_waiters: [from | data.ready_waiters]}}
    end
  end

  def handle_event({:call, from}, :await_ready, :faulted, _data),
    do: {:keep_state_and_data, reply(from, {:error, :reconciliation_required})}

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

  def handle_event(type, {:turn, _token, _signal, _context, _deadline, reply_gate}, :faulted, data),
    do: reject_turn(type, :reconciliation_required, data, reply_gate)

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

  def handle_event({:call, from}, :status, phase, data) do
    {:keep_state_and_data, [{:reply, from, public_status(phase, data)}]}
  end

  def handle_event({:call, from}, :ownership, _phase, data) do
    result =
      case data.parent do
        nil -> {:ok, nil}
        %{kind: :dynamic_ownership} = parent -> {:ok, public_ownership(data.agent_address, parent)}
        _other -> {:error, :ownership_not_transferable}
      end

    {:keep_state_and_data, reply(from, result)}
  end

  def handle_event({:call, from}, :ownership_context, _phase, data) do
    context = %{
      activation: data.activation,
      jido: data.jido,
      partition: data.partition,
      parent_activation: if(data.parent, do: data.parent.activation)
    }

    {:keep_state_and_data, reply(from, {:ok, context})}
  end

  def handle_event(
        {:call, from},
        {:transfer_ownership, owner, expected, request_id},
        _phase,
        data
      ) do
    case change_ownership(data, owner, expected, request_id) do
      {:ok, ownership, data} -> {:keep_state, data, reply(from, {:ok, ownership})}
      {:error, reason} -> {:keep_state_and_data, reply(from, {:error, reason})}
    end
  end

  def handle_event(
        {:call, from},
        {:cancel, id},
        :handoff_pending,
        %{pending_handoff: %{receipt: receipt} = pending} = data
      ) do
    cond do
      id != :active and id != receipt.id and id != pending.active.turn_id ->
        {:keep_state_and_data, reply(from, {:error, :stale_turn})}

      true ->
        cancel_pending_handoff(data, pending, from)
    end
  end

  def handle_event({:call, from}, {:cancel, _id}, :idle, _data),
    do: {:keep_state_and_data, reply(from, {:error, :not_running})}

  def handle_event({:call, from}, {:cancel, _id}, :waiting, %{admission_mode: :blocked}),
    do: {:keep_state_and_data, reply(from, {:error, :unsafe_resume})}

  def handle_event(
        {:call, from} = type,
        {:cancel, id},
        :saving,
        %{active: %{operation: %{kind: :durable_release}}} = data
      ) do
    cond do
      id != :active and id != data.active.turn_id and id != data.active.handoff_receipt.id ->
        {:keep_state_and_data, reply(from, {:error, :stale_turn})}

      Lifecycle.reentrant?(type, data) ->
        {:keep_state_and_data, reply(from, {:error, :reentrant_turn})}

      true ->
        {:keep_state, update_in(data.active.cancel_waiters, &[from | &1])}
    end
  end

  def handle_event({:call, from}, {:cancel, _id}, phase, _data)
      when phase in [:saving, :hibernating],
      do: {:keep_state_and_data, reply(from, {:error, :commit_in_progress})}

  def handle_event(
        {:call, from} = type,
        {:cancel, id},
        :effects,
        %{active: %{result: {:handoff, _, _, _}}} = data
      ) do
    cond do
      id != :active and id != data.active.turn_id and id != data.active.handoff_receipt.id ->
        {:keep_state_and_data, reply(from, {:error, :stale_turn})}

      Lifecycle.reentrant?(type, data) ->
        {:keep_state_and_data, reply(from, {:error, :reentrant_turn})}

      true ->
        data = update_in(data.active.cancel_waiters, &[from | &1])
        abort_turn(:effects, data, :cancelled)
    end
  end

  def handle_event({:call, from}, {:cancel, _id}, phase, _data) when phase in [:effects],
    do: {:keep_state_and_data, reply(from, {:error, :not_running})}

  def handle_event(:info, {:turn_timeout, _id}, phase, _data)
      when phase in [:saving, :hibernating, :effects],
      do: :keep_state_and_data

  def handle_event(:info, {:turn_timeout, _id}, :waiting, %{admission_mode: :blocked}),
    do: :keep_state_and_data

  def handle_event(:info, {:persistence_timeout, id}, :saving, %{active: %{turn_id: id}} = data),
    do: stop_durable(data, :indeterminate)

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

  def handle_event({:call, from} = type, {:cancel, id}, phase, data) do
    cond do
      id != :active and id != data.active.turn_id and id != handoff_turn_id(data.active) and
          id != handoff_predecessor_id(data.active) ->
        {:keep_state_and_data, reply(from, {:error, :stale_turn})}

      Lifecycle.reentrant?(type, data) ->
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
          Process.send_after(self(), {:turn_timeout, id}, min(remaining, Lifecycle.max_timeout()))

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

  def handle_event(
        type,
        {:turn, token, _signal, _context, _deadline, reply_gate},
        :handoff_pending,
        data
      )
      when type == :cast or (is_tuple(type) and elem(type, 0) == :call) do
    postpone_turn(type, token, data, reply_gate)
  end

  def handle_event(type, {:turn, token, signal, context, deadline, reply_gate}, :idle, data)
      when type == :cast or (is_tuple(type) and elem(type, 0) == :call) do
    data = %{
      data
      | postponed: MapSet.delete(data.postponed, token),
        queued_from: Map.delete(data.queued_from, token)
    }

    with :ok <- Lifecycle.admission_status(deadline) do
      case Continuation.retry(data.server_turn, signal) do
        :new ->
          start_turn(type, signal, context, data, {:turn, token}, reply_gate)

        {:ok, result} ->
          ReplyGate.done(reply_gate)

          case type do
            :cast -> {:keep_state, arm_idle(data)}
            {:call, from} -> {:keep_state, arm_idle(data), reply(from, {:ok, result})}
          end

        {:completed, turn_id} ->
          ReplyGate.done(reply_gate)
          result = completed_retry_result(data, turn_id)

          case type do
            :cast -> {:keep_state, arm_idle(data)}
            {:call, from} -> {:keep_state, arm_idle(data), reply(from, {:ok, result})}
          end

        {:error, reason} ->
          reject_turn(type, reason, data, reply_gate)
      end
    else
      {:error, reason} -> reject_turn(type, reason, data, reply_gate)
    end
  end

  def handle_event(
        type,
        {:turn, token, signal, _context, deadline, reply_gate},
        :waiting,
        %{active: %{operation: nil}} = data
      )
      when type == :cast or (is_tuple(type) and elem(type, 0) == :call) do
    data = %{
      data
      | postponed: MapSet.delete(data.postponed, token),
        queued_from: Map.delete(data.queued_from, token)
    }

    with :ok <- Lifecycle.admission_status(deadline),
         false <- durable_wake?(signal),
         %Jido.Exec.Wait{} = wait <-
           Enum.find(data.active.waits, &Jido.Exec.Wait.matches?(&1, signal.type, signal.data)),
         {:ok, input} <- Jido.Exec.Wait.input(wait.id, signal) do
      from = if match?({:call, _}, type), do: elem(type, 1), else: nil
      cancel_timer(data.active)

      active = %{
        data.active
        | from: from,
          requester: reply_gate,
          signal_id: signal.id,
          resume_input: input,
          resume_kind: :event,
          wait_from: nil,
          deadline:
            if(data.turn_timeout == :infinity,
              do: :infinity,
              else: System.monotonic_time(:millisecond) + data.turn_timeout
            ),
          timer:
            if(data.turn_timeout == :infinity,
              do: nil,
              else:
                Process.send_after(
                  self(),
                  {:turn_timeout, data.active.turn_id},
                  min(data.turn_timeout, Lifecycle.max_timeout())
                )
            )
      }

      receipt = Continuation.put_resume_input!(data.server_turn, input)
      data = %{data | active: active, server_turn: receipt}
      durable_write(:durable_resume_intent, data, data.agent, receipt)
    else
      true -> resume_durable_timer(data, signal, type, reply_gate)
      nil -> reject_turn(type, :wait_not_matched, data, reply_gate)
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
             :effects
           ] and
             (type == :cast or (is_tuple(type) and elem(type, 0) == :call)) do
    admission =
      if Lifecycle.reentrant?(type, data),
        do: {:error, :reentrant_turn},
        else: Lifecycle.admission_status(deadline)

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
           :durable_prepare,
           :durable_accept,
           :durable_release,
           :durable_terminal,
           :durable_wait,
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

      phase not in [:cleaning, :saving, :effects] and expired?(data.active) ->
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
        :partition,
        :persistence
      ])
      |> Map.merge(%{requester: active.requester, durable: active.durable})

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

        dispatch = Signal.Dispatch.inherit_bus_scope(parent.dispatch, data.jido)
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
    do: {:keep_state, %{data | child_monitors: forget_child_monitors(data.child_monitors, tag, token)}}

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

  def handle_event(
        :internal,
        :recover_turn,
        :idle,
        %{server_turn: %{status: :released} = receipt} = data
      ) do
    start_turn(:cast, receipt.signal, receipt.context, data, {:handoff, receipt})
  end

  def handle_event(:internal, :recover_turn, _phase, _data), do: :keep_state_and_data

  def handle_event(:info, {:durable_advance, id}, :starting, %{active: %{turn_id: id}}),
    do: {:keep_state_and_data, [:postpone]}

  def handle_event(:info, {:durable_advance, id}, :running, %{active: %{turn_id: id}} = data),
    do: durable_advance(data)

  def handle_event(:internal, :durable_advance, :running, data), do: durable_advance(data)

  def handle_event(
        :info,
        {:durable_storage_timeout, id},
        _phase,
        %{active: %{turn_id: id}} = data
      ),
      do: stop_durable(data, :indeterminate)

  def handle_event(
        :info,
        {:handoff_successor, id},
        :handoff_pending,
        %{pending_handoff: %{receipt: %{id: id, status: :released} = receipt} = pending} = data
      ) do
    type = if pending.from, do: {:call, pending.from}, else: :cast

    start_turn(
      type,
      receipt.signal,
      receipt.context,
      %{data | pending_handoff: nil},
      {:handoff, receipt},
      pending.requester
    )
  end

  def handle_event(:info, _message, _phase, _data), do: :keep_state_and_data

  # Without this clause a FunctionClauseError puts the data in the stacktrace.
  def handle_event(_type, _event, phase, _data), do: {:stop, {:unexpected_event, phase}}

  defp public_status(phase, data) do
    {:message_queue_len, mailbox} = Process.info(self(), :message_queue_len)
    Status.new(phase, data, mailbox)
  end

  defp durable_wake?(%Jido.Signal{type: "jido.durable.wake", data: data}) do
    is_map(data) and is_binary(data[:turn_id]) and is_binary(data[:wait_id]) and
      is_integer(data[:deadline])
  end

  defp durable_wake?(_signal), do: false

  defp resume_durable_timer(data, signal, type, reply_gate) do
    wake = signal.data

    valid? =
      wake.turn_id == data.active.turn_id and
        Enum.any?(data.active.waits, fn wait ->
          wait.id == wake.wait_id and
            Enum.any?(wait.options, &(&1.deadline == wake.deadline))
        end) and wake.deadline <= System.system_time(:millisecond)

    if valid? do
      from = if match?({:call, _}, type), do: elem(type, 1), else: nil
      cancel_timer(data.active)

      active = %{
        data.active
        | from: from,
          requester: reply_gate,
          signal_id: signal.id,
          deadline:
            if(data.turn_timeout == :infinity,
              do: :infinity,
              else: System.monotonic_time(:millisecond) + data.turn_timeout
            ),
          timer:
            if(data.turn_timeout == :infinity,
              do: nil,
              else:
                Process.send_after(
                  self(),
                  {:turn_timeout, data.active.turn_id},
                  min(data.turn_timeout, Lifecycle.max_timeout())
                )
            )
      }

      {:ok, input} = Jido.Exec.Wait.input(wake.wait_id, signal)
      receipt = Continuation.put_resume_input!(data.server_turn, input)

      data = %{
        data
        | server_turn: receipt,
          active: %{active | resume_input: input, resume_kind: :timer}
      }

      durable_write(:durable_resume_intent, data, data.agent, receipt)
    else
      reject_turn(type, :stale_wait, data, reply_gate)
    end
  end

  defp bootstrap_timeout(%{bootstrap: %{kind: :persistence}}), do: :persistence_timeout
  defp bootstrap_timeout(_data), do: :readiness_timeout

  defp finish_bootstrap(
         {:ok, agent, revision, agent_revision, config, turn},
         %{bootstrap: %{kind: :persistence}} = data
       ) do
    Lifecycle.restore(data.activation_state, agent, revision, agent_revision)

    {:ok, specs} =
      Jido.Plugin.Normalizer.normalize_runtime(
        Jido.Agent.Plugin.declarations(agent),
        data.plugin_runtime_options
      )

    data = %{
      data
      | agent: agent,
        plugin_specs: specs,
        state_version: revision,
        agent_revision: agent_revision,
        persistence_revision: revision,
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

  defp finish_bootstrap({:error, reason}, data) do
    # A Plugin or topology start fails after Lifecycle.start/2 has returned.
    Lifecycle.record_start_failure(reason, [data.activation, self()])
    {:stop, {:shutdown, reason}, data}
  end

  # OTP crash reports and :sys.get_status/1 read these terms. Agent state and
  # Signal data must not reach them.
  @impl true
  def format_status(status), do: Map.new(status, &redact_status/1)

  defp redact_status({:data, %{agent: agent} = data}) do
    {:data,
     %{
       agent_id: agent.id,
       agent_module: agent.module,
       state_version: data.state_version,
       redacted: true
     }}
  end

  defp redact_status({:data, _data}), do: {:data, :redacted}

  defp redact_status({key, events}) when key in [:queue, :postponed, :timeouts] and is_list(events),
    do: {key, Enum.map(events, &redact_event/1)}

  defp redact_status({:log, _log}), do: {:log, []}
  defp redact_status({:reason, reason}), do: {:reason, log_reason(reason)}
  defp redact_status(entry), do: entry

  defp redact_event({type, _content}), do: {type, :redacted}
  defp redact_event(_event), do: :redacted

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
    AgentServerTelemetry.lifecycle(:stop, data.agent.id)
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
        {:handoff, receipt} -> receipt.id
        {:turn, turn_id} -> turn_id
      end

    timeout =
      case mode do
        {:restore, %{expires_at: :infinity}} -> :infinity
        {:restore, receipt} -> max(0, receipt.expires_at - System.system_time(:millisecond))
        {:handoff, %{expires_at: :infinity}} -> :infinity
        {:handoff, receipt} -> max(0, receipt.expires_at - System.system_time(:millisecond))
        _ -> data.turn_timeout
      end

    agent = data.agent
    trace = TraceContext.begin_turn(signal)

    span =
      AgentServerTelemetry.start_turn(
        Map.merge(Jido.Trace.metadata(trace), %{
          agent_id: agent.id,
          agent_module: agent.module,
          agent_name: agent.name,
          signal_type: signal.type,
          turn_id: turn_id,
          signal_id: signal.id
        })
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
      reply: nil,
      failure_stage: nil,
      turn_id: turn_id,
      chain_id:
        case mode do
          {:handoff, receipt} -> receipt.chain_id
          _ -> turn_id
        end,
      chain_order:
        case mode do
          {:handoff, receipt} -> receipt.chain_order
          _ -> 0
        end,
      handoff_predecessor_id:
        case mode do
          {:handoff, receipt} -> receipt.predecessor_id
          _ -> nil
        end,
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
      persisted:
        match?({:restore, _}, mode) or
          (match?({:handoff, _}, mode) and data.persistence not in [nil, false]),
      durable_finalized: false,
      durable_storage: nil,
      durable_next: nil,
      advance_pending: false,
      resume_input:
        case mode do
          {:restore, %{resume: %{input: input, result: nil}}} -> input
          _other -> nil
        end,
      resume_kind:
        case mode do
          {:restore, %{resume: %{input: %{event: "jido.durable.wake"}, result: nil}}} -> :timer
          {:restore, %{resume: %{input: _input, result: nil}}} -> :event
          _other -> nil
        end,
      waits: [],
      wait_deadline: nil,
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
          else: Process.send_after(self(), {:turn_timeout, turn_id}, min(timeout, Lifecycle.max_timeout()))
        )
    }

    case mode do
      {:restore, receipt} ->
        operation(:restore_turn, %{data | active: active}, fn ->
          Lifecycle.restore_continuation(agent, receipt, context, data.plugin_specs)
        end)

      {:handoff, receipt} ->
        operation(:restore_handoff, %{data | active: active, pending_handoff: nil}, fn ->
          Lifecycle.restore_handoff(agent, receipt, context, data.plugin_specs)
        end)

      {:turn, _turn_id} ->
        operation(:prepare, %{data | active: active}, fn ->
          prepare_turn(agent, signal, context, data)
        end)
    end
  end

  defp prepare_turn(agent, signal, context, data) do
    with {:ok, inputs} <- Jido.Agent.Plugin.prepare(agent, signal, data.plugin_specs),
         {:ok, command} <- Command.new_trusted_agent(agent, signal, context),
         command = %{command | plugin_inputs: inputs},
         {:ok, admitted} <- Plugin.admit(command, data),
         {:ok, prepared} <-
           AgentRunner.prepare_admitted(
             admitted,
             signal,
             [],
             data.plugin_specs
           ) do
      {:ok, prepared}
    else
      {:error, _stage, reason} -> {:error, reason}
      {:error, _} = error -> error
    end
  end

  defp accept_handoff(instruction, data), do: Lifecycle.accept_handoff(data, instruction)

  defp release_handoff(data) do
    receipt = data.active.handoff_receipt
    signal = receipt.signal
    context = receipt.context

    with {:ok, inputs} <- Jido.Agent.Plugin.prepare(data.agent, signal, data.plugin_specs),
         {:ok, command} <- Command.new_trusted_agent(data.agent, signal, context),
         command = %{command | plugin_inputs: inputs},
         {:ok, admitted} <- Plugin.admit(command, data),
         {:ok, prepared} <-
           AgentRunner.prepare_admitted_handoff(
             admitted,
             signal,
             receipt.instruction,
             [],
             data.plugin_specs
           ),
         {:ok, released} <- Lifecycle.release_handoff(data, receipt, prepared) do
      {:ok, released}
    else
      {:error, _stage, reason} -> {:error, reason}
      {:error, _} = error -> error
    end
  end

  defp durable_write(kind, data, agent, receipt) do
    durable_operation(kind, data, fn ->
      Lifecycle.save(data, agent, data.state_version + 1, data.state_version, receipt)
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
           data.state_version + 1,
           data.agent_revision
         ) do
      :ok ->
        revision = data.state_version + 1
        {:ok, %{data | state_version: revision, persistence_revision: revision}}

      error ->
        error
    end
  end

  defp start_durable_worker(data) do
    data = put_in(data.active.worker_id, Lifecycle.execution_identity(data))
    owner = self()
    hooks = Lifecycle.execution_hooks(Keyword.get(data.exec_opts, :hooks, []), TraceContext.get())
    policy = Lifecycle.execution_policy(data.exec_opts)

    durable_operation(:durable_start, data, fn ->
      Lifecycle.start_execution(data, owner, hooks, policy)
    end)
  end

  defp durable_advance(%{active: %{operation: nil}} = data),
    do:
      durable_operation(:durable_advance, data, fn ->
        Lifecycle.advance_execution(data.runner, data.active.worker_id)
      end)

  defp durable_advance(data), do: {:keep_state, put_in(data.active.advance_pending, true)}

  defp operation(kind, data, fun) do
    captured = TraceContext.capture()
    task = Task.async(fn -> TraceContext.with_context(captured, fun) end)

    phases = %{
      prepare: :preparing,
      restore_turn: :preparing,
      restore_handoff: :preparing,
      prepare_handoff: :preparing,
      release_handoff: :preparing,
      durable_prepare: :saving,
      durable_accept: :saving,
      durable_release: :saving,
      durable_resume_intent: :saving,
      durable_start: :starting,
      durable_advance: :running,
      durable_terminal: :saving,
      durable_wait: :saving,
      durable_suspend: :starting,
      durable_input: :starting,
      start: :starting,
      execute: :starting,
      settle: :settling,
      cleanup: :cleaning,
      save: :saving,
      commit_hook: :effects,
      effect: :effects
    }

    {:next_state, Map.fetch!(phases, kind), put_in(data.active.operation, %{kind: kind, task: task})}
  end

  defp operation_result(kind, {:ok, prepared}, data)
       when kind in [:prepare, :restore_turn, :restore_handoff] do
    data = put_in(data.active.prepared, prepared)

    case Lifecycle.durable_instruction(prepared) do
      {:ok, %{kind: :flow}} when data.persistence not in [nil, false] ->
        if kind in [:restore_turn, :restore_handoff] do
          start_durable_worker(put_in(data.active.durable, true))
        else
          case Lifecycle.accept_continuation(data, prepared) do
            {:ok, receipt} ->
              data = %{
                data
                | server_turn: receipt,
                  active: %{data.active | durable: true, persisted: true}
              }

              owner = self()

              durable_operation(:durable_prepare, data, fn ->
                Lifecycle.prepare_execution(data, receipt, owner)
              end)

            {:error, reason} ->
              cleanup(data, {:error, reason})
          end
        end

      _instruction ->
        owner = self()
        runner = data.runner
        id = data.active.turn_id
        exec_opts = data.exec_opts
        operation(:start, data, fn -> start_worker(runner, id, owner, prepared, exec_opts) end)
    end
  end

  defp operation_result(kind, {:error, reason}, data)
       when kind in [:restore_turn, :restore_handoff],
       do: stop_durable(data, reason)

  defp operation_result(:prepare_handoff, {:ok, receipt}, data) do
    result = data.active.result

    data =
      data
      |> put_in([:active, :handoff_receipt], receipt)
      |> then(fn data ->
        if data.persistence in [nil, false], do: data, else: %{data | server_turn: receipt}
      end)

    finish(data, result)
  end

  defp operation_result(:prepare_handoff, {:error, reason}, data),
    do: cleanup(put_in(data.active.failure_stage, :preparing), {:error, reason})

  defp operation_result(:release_handoff, {:ok, receipt}, data) do
    data = put_in(data.active.handoff_receipt, receipt)

    if data.persistence in [nil, false] do
      handoff_transition(data)
    else
      data = %{data | server_turn: receipt}
      durable_write(:durable_release, data, data.agent, receipt)
    end
  end

  defp operation_result(:release_handoff, {:error, reason}, data),
    do: fail_handoff(put_in(data.active.failure_stage, :preparing), reason)

  defp operation_result(:durable_accept, :ok, data) do
    case publish_durable_revision(data) do
      {:ok, data} -> start_durable_worker(data)
      {:error, reason} -> stop_durable(data, reason)
    end
  end

  defp operation_result(:durable_prepare, :ok, data),
    do: durable_write(:durable_accept, data, data.agent, data.server_turn)

  defp operation_result(:durable_release, :ok, data) do
    case publish_durable_revision(data) do
      {:ok, %{active: %{cancel_waiters: [_ | _]}} = data} ->
        abort_turn(:effects, data, :cancelled)

      {:ok, data} ->
        handoff_transition(data)

      {:error, reason} ->
        stop_durable(data, reason)
    end
  end

  defp operation_result(:durable_resume_intent, :ok, data) do
    case publish_durable_revision(data) do
      {:ok, %{active: %{resume_kind: :timer}} = data} ->
        start_durable_worker(data)

      {:ok, %{active: %{resume_input: input}} = data} ->
        durable_operation(:durable_input, data, fn -> Lifecycle.deliver_wait_input(data, input) end)

      {:error, reason} ->
        stop_durable(data, reason)
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
        {:next_state, :running, %{data | active: active}, [{:next_event, :internal, :durable_advance}]}

      {:error, reason} ->
        stop_durable(%{data | active: active}, reason)
    end
  end

  defp operation_result(
         :durable_start,
         {:waiting, waits, deadline},
         %{active: %{resume_kind: :event, resume_input: input}} = data
       ) do
    data =
      data
      |> put_in([:active, :waits], waits)
      |> put_in([:active, :wait_deadline], deadline)

    durable_operation(:durable_input, data, fn -> Lifecycle.deliver_wait_input(data, input) end)
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
      Lifecycle.suspend_execution(data.runner, data.active.worker_id)
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
    {:next_state, phase, data, if(from, do: reply(from, :ok), else: [])}
  end

  defp operation_result(:durable_input, {:rejected, reason}, data) do
    from = data.active.wait_from
    data = put_in(data.active.wait_from, nil)
    {:next_state, :waiting, data, reply(from, {:error, reason})}
  end

  defp operation_result(:durable_advance, :running, data) do
    pending = Map.get(data.active, :advance_pending, false)
    data = put_in(data.active.advance_pending, false)

    {:next_state, :running, data, if(pending, do: [{:next_event, :internal, :durable_advance}], else: [])}
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

  defp operation_result(:durable_wait, :ok, data) do
    case publish_durable_revision(data) do
      {:ok, data} -> enter_waiting(data)
      {:error, reason} -> stop_durable(data, reason)
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
              :durable_prepare,
              :durable_release,
              :durable_start,
              :durable_advance,
              :durable_terminal,
              :durable_wait,
              :durable_suspend,
              :durable_input
            ],
       do: stop_durable(data, reason)

  defp operation_result(:start, {:ok, worker, input, context}, data) do
    # Publish ownership before execution can call back into this server.
    active = %{data.active | worker: worker, worker_ref: Process.monitor(worker)}
    runner = data.runner
    id = active.worker_id
    policy = Lifecycle.execution_policy(data.exec_opts)

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

    case Lifecycle.write_result(result, deadline) do
      :ok -> publish_commit(data, data.active.result)
      {:error, reason} -> stop_durable(data, reason)
    end
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

  defp abort_turn(phase, %{active: %{persisted: true, durable_finalized: false}} = data, reason) do
    if data.active.operation, do: Task.shutdown(data.active.operation.task, :brutal_kill)
    if data.active.durable_storage, do: Process.cancel_timer(elem(data.active.durable_storage, 0))

    if phase == :effects and data.active.effect_timer,
      do: Process.cancel_timer(data.active.effect_timer)

    data = put_in(data.active.operation, nil)
    if data.active.wait_from, do: :gen_statem.reply(data.active.wait_from, {:error, reason})
    data = put_in(data.active.wait_from, nil)
    status = if reason == :cancelled, do: :cancelled, else: :failed

    receipt =
      data.server_turn
      |> Continuation.put_status!(status)
      |> put_resume_result(data, {:error, reason}, data.agent_revision, data.state_version + 1)

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

    if phase == :effects and data.active.effect_timer,
      do: Process.cancel_timer(data.active.effect_timer)

    data = put_in(data.active.operation, nil)
    data = put_in(data.active.failure_stage, phase)
    cleanup(put_in(data.active.abort_reason, reason), nil)
  end

  defp cleanup(data, result) do
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
    instruction = prepared.instruction

    with {:ok, input} <- execution_input(instruction),
         {:ok, workflow} <- Jido.Exec.compile(%{instruction | context: %{}}, []),
         :ok <- Jido.Exec.Node.Wait.validate_host(workflow),
         {:ok, worker} <-
           Runner.start_workflow(runner, id, workflow,
             owner: owner,
             max_concurrency: Keyword.get(exec_opts, :max_concurrency, 1),
             checkpoint_strategy: :manual,
             runnable_order: &execution_order/1,
             hooks: Lifecycle.execution_hooks(Keyword.get(exec_opts, :hooks, []), TraceContext.get()),
             on_complete: fn ^id, _workflow -> send(owner, {:worker_complete, id}) end
           ) do
      {:ok, worker, input, instruction.context}
    end
  end

  defp execution_input(%Jido.Instruction{kind: :flow} = instruction) do
    with {:ok, params} <-
           Jido.Exec.Validation.input(instruction.target, instruction.params, %{
             phase: :flow_input
           }),
         do: {:ok, params}
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
             do: Jido.Exec.Result.project(workflow)
      else
        with {:ok, observation} <- Runner.execution(runner, active.worker_id, active.execution_id),
             {:ok, workflow} <- Runner.get_workflow(runner, active.worker_id),
             do: Jido.Exec.result(workflow, observation)
      end

    case AgentRunner.finish_for_server(active.prepared, result) do
      {:error, _stage, reason} ->
        {:error, if(match?({:error, _}, result), do: :running, else: :settling), reason}

      {:ok, candidate, directives} ->
        with :ok <- immutable_definition(config.agent, candidate),
             :ok <- Effects.validate_batch(directives, %{config | agent: candidate}) do
          {:ok, candidate, directives}
        else
          {:error, reason} -> {:error, :directives, reason}
        end

      {:handoff, candidate, instruction, directives} ->
        with :ok <- immutable_definition(config.agent, candidate),
             :ok <- Effects.validate_batch(directives, %{config | agent: candidate}) do
          {:handoff, candidate, instruction, directives}
        else
          {:error, reason} -> {:error, :directives, reason}
        end
    end
  end

  defp immutable_definition(source, candidate) do
    if Agent.definition(source) == Agent.definition(candidate),
      do: :ok,
      else: {:error, :agent_definition_changed}
  end

  defp execution_error(message, reason),
    do: Jido.Error.execution_error(message, %{reason: reason})

  defp stop_failed(data, _error, :effects) do
    if data.active.operation, do: Task.shutdown(data.active.operation.task, :brutal_kill)
    data = record_effects(data, :indeterminate)
    {:stop, {:shutdown, :effect_lifecycle_failed}, %{data | active: nil}}
  end

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

  defp postpone_turn(type, token, data, reply_gate) do
    case Lifecycle.queue_decision(data.postponed, token, data.max_postponed_signals) do
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

  defp reject_turn(type, reason, data, reply_gate) do
    ReplyGate.done(reply_gate)
    {:keep_state, data, turn_rejection(type, reason, data)}
  end

  defp turn_rejection(:cast, reason, data) do
    Logger.warning("AgentServer cast dropped", agent_id: data.agent.id, reason: reason)
    []
  end

  defp turn_rejection({:call, from}, reason, _data), do: reply(from, {:error, reason})

  defp finish(
         %{active: %{persisted: true, durable_finalized: false}} = data,
         {:error, _} = result
       ) do
    receipt =
      data.server_turn
      |> Continuation.put_status!(:failed)
      |> put_resume_result(data, result, data.agent_revision, data.state_version + 1)

    data =
      data
      |> Map.put(:server_turn, receipt)
      |> put_in([:active, :durable_next], {:finish, result})

    durable_write(:durable_terminal, data, data.agent, receipt)
  end

  defp finish(
         %{active: active} = data,
         {:handoff, _candidate, instruction, _directives} = result
       )
       when not is_map_key(active, :handoff_receipt) do
    active = Map.merge(active, %{result: result, handoff_id: Jido.Id.uuid7()})

    operation(:prepare_handoff, %{data | active: active}, fn ->
      accept_handoff(instruction, %{data | active: active})
    end)
  end

  defp finish(
         %{persistence: persistence} = data,
         {:handoff, candidate, _instruction, _directives} = result
       )
       when persistence not in [nil, false] do
    cancel_timer(data.active)
    deadline = System.monotonic_time(:millisecond) + data.persistence_timeout

    timer =
      Process.send_after(
        self(),
        {:persistence_timeout, data.active.turn_id},
        data.persistence_timeout
      )

    active =
      Map.merge(data.active, %{result: result, storage: {timer, deadline}, persisted: true})

    receipt = data.active.handoff_receipt
    data = %{data | server_turn: receipt}

    operation(:save, %{data | active: active}, fn ->
      Lifecycle.save(
        data,
        candidate,
        data.state_version + 1,
        data.state_version,
        receipt,
        agent_revision: data.agent_revision + 1
      )
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
      if data.active.persisted,
        do: Continuation.put_status!(data.server_turn, :completed),
        else: data.server_turn

    receipt =
      put_resume_result(
        receipt,
        data,
        result,
        data.agent_revision + 1,
        data.state_version + 1
      )

    data = %{data | server_turn: receipt}

    operation(:save, %{data | active: active}, fn ->
      Lifecycle.save(
        data,
        candidate,
        data.state_version + 1,
        data.state_version,
        receipt,
        agent_revision: data.agent_revision + 1
      )
    end)
  end

  defp finish(data, {:ok, _, _} = result), do: publish_commit(data, result)
  defp finish(data, {:handoff, _, _, _} = result), do: publish_commit(data, result)
  defp finish(data, result), do: finish_result(data, result)

  defp stop_durable(data, reason) do
    if reconciliation_failure?(reason) do
      fault_durable(data, reason)
    else
      stop_failed(data, execution_error("Required durable commit failed", reason), :saving)
    end
  end

  defp fault_durable(data, reason) do
    if data.active.operation, do: Task.shutdown(data.active.operation.task, :brutal_kill)

    Enum.each([Map.get(data.active, :storage), Map.get(data.active, :durable_storage)], fn
      {timer, _deadline} when is_reference(timer) -> Process.cancel_timer(timer)
      _other -> :ok
    end)

    cancel_timer(data.active)

    data =
      data
      |> put_in([:active, :operation], nil)
      |> put_in([:active, :result], {:error, reason})
      |> set_admission(:blocked)
      |> record_outcome(:indeterminate, :saving, false, 0)

    mark_reconciliation_required(data, reason)

    replies =
      accepted_reply(data, :uncertain) ++
        cancel_replies(data.active, {:error, :reconciliation_required})

    ReplyGate.done(data.active.requester)
    TraceContext.clear()

    {:next_state, :faulted, %{data | active: nil}, replies}
  end

  defp reconciliation_failure?(:conflict), do: true
  defp reconciliation_failure?(:indeterminate), do: true
  defp reconciliation_failure?(:uncertain), do: true
  defp reconciliation_failure?({kind, _reason}) when kind in [:indeterminate, :uncertain], do: true

  defp reconciliation_failure?(%{details: %{reason: reason}}),
    do: reconciliation_failure?(reason)

  defp reconciliation_failure?(_reason), do: false

  defp mark_reconciliation_required(%{jido: jido, agent_address: address}, reason)
       when is_atom(jido) and not is_nil(jido) do
    _ = Jido.Instance.RuntimeStore.put(jido, :agent_reconciliation, address, reason)
    :ok
  end

  defp mark_reconciliation_required(_data, _reason), do: :ok

  defp publish_commit(data, result) do
    {candidate, _directives} = success_candidate_and_directives(result)

    case ServerSupervisor.publish_checkpoint(
           data.activation_state,
           candidate,
           data.state_version + 1,
           data.agent_revision + 1
         ) do
      :ok ->
        finish_result(data, result)

      {:error, reason} ->
        stop_failed(data, execution_error("Local checkpoint failed", reason), :checkpoint)
    end
  end

  defp finish_result(data, result) do
    if data.active.durable and
         (data.active.durable_finalized or data.server_turn.status == :completed),
       do: ContinuationStore.collect(data.jido, data.active.worker_id)

    {next, status, stage, count} =
      case result do
        result when elem(result, 0) in [:ok, :handoff] ->
          {candidate, directives} = success_candidate_and_directives(result)

          {%{
             data
             | agent: candidate,
               state_version: data.state_version + 1,
               agent_revision: data.agent_revision + 1,
               persistence_revision:
                 if(data.persistence in [nil, false],
                   do: nil,
                   else: data.state_version + 1
                 )
           }, :succeeded, :commit, length(directives)}

        {:error, reason} ->
          if is_nil(data.active.from),
            do:
              Logger.warning(
                "AgentServer cast turn failed: signal type #{data.active.signal_type}, " <>
                  "reason #{inspect(log_reason(reason))}",
                agent_id: data.agent.id,
                turn_id: data.active.turn_id
              )

          status = Lifecycle.outcome_status(reason)
          {data, status, data.active.failure_stage || :cleaning, 0}
      end

    cancel_timer(data.active)

    next =
      next
      |> put_in([:active, :result], result)
      |> record_outcome(status, stage, status == :succeeded, count)

    case result do
      result when elem(result, 0) in [:ok, :handoff] ->
        {_candidate, directives} = success_candidate_and_directives(result)

        if directives != [] or PluginCallbacks.commit_specs(next.plugin_specs) != [],
          do: begin_effects(next, directives),
          else: complete_terminal(next)

      {:error, _} when status == :failed ->
        complete_terminal(next)

      _ ->
        complete_terminal(next)
    end
  end

  defp success_candidate_and_directives({:ok, candidate, directives}),
    do: {candidate, directives}

  defp success_candidate_and_directives({:handoff, candidate, _instruction, directives}),
    do: {candidate, directives}

  defp begin_effects(data, directives) do
    {reply_signal, directives} = take_reply(directives)
    reply_signal = prepared_reply(reply_signal, effect_context(data))
    data = put_in(data.active.reply, reply_signal)
    active = data.active

    hooks = PluginCallbacks.commit_specs(Map.get(active, :commit_plugins, data.plugin_specs))
    timeout = if hooks == [], do: data.directive_timeout, else: data.commit_timeout
    timer_kind = if hooks == [], do: :effect_timeout, else: :commit_timeout

    replies =
      commit_replies(%{
        data
        | active: %{active | commit_hooks: hooks, effects: directives}
      })

    active = %{
      active
      | from: if(handoff_result?(active.result), do: active.from, else: nil),
        commit_hooks: hooks,
        cancel_waiters: [],
        effects: directives,
        effect_deadline: System.monotonic_time(:millisecond) + timeout,
        effect_timer: Process.send_after(self(), {timer_kind, active.turn_id}, timeout)
    }

    data = %{data | active: active}

    AgentServerTelemetry.start_effects(active.span.metadata, length(directives))

    {:next_state, :effects, data, replies ++ [{:next_event, :internal, :effect_next}]}
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
        context = effect_context(data)

        operation(:effect, data, fn ->
          case Plugin.dispatch(data, active, directive) do
            :unowned -> Effects.run(directive, nil, context)
            result -> result
          end
        end)
    end
  end

  defp record_effects(data, status) do
    active = data.active
    outcome = Effects.outcome(active, data.state_version, status)

    AgentServerTelemetry.finish_effects(
      active.span.metadata,
      status,
      outcome.stage,
      active.effect_index,
      length(active.effects)
    )

    data |> Map.put(:last_effect_outcome, outcome) |> put_in([:active, :effect_outcome], outcome)
  end

  # A connection destination can be mid-restart. Treat this as a failed effect,
  # as a root output does. No Turn owns this delivery, so turn_id is nil.
  defp topology_delivery_failed(data, signal, reason) do
    Logger.warning(
      "AgentServer topology delivery failed: signal type #{signal.type}, " <>
        "reason #{inspect(log_reason(reason))}",
      agent_id: data.agent.id
    )

    %{
      data
      | last_effect_outcome: %{
          turn_id: nil,
          status: :failed,
          completed: 0,
          total: 1,
          committed_version: data.state_version,
          stage: :directive
        }
    }
  end

  # Logs name a failure without carrying the values inside its reason.
  defp log_reason(reason) when is_atom(reason), do: reason
  defp log_reason(%{code: code}) when is_atom(code) and not is_nil(code), do: code
  defp log_reason(%{details: %{code: code}}) when is_atom(code) and not is_nil(code), do: code
  defp log_reason(%{__struct__: module}), do: module
  defp log_reason(reason) when is_tuple(reason) and is_atom(elem(reason, 0)), do: elem(reason, 0)
  defp log_reason(_reason), do: :unknown

  defp finish_effects(data, status) do
    Process.cancel_timer(data.active.effect_timer)
    data = record_effects(data, status)

    cond do
      handoff_result?(data.active.result) and status == :succeeded ->
        begin_handoff_release(data)

      handoff_result?(data.active.result) ->
        fail_handoff(data, execution_error("Handoff predecessor effects failed", status))

      true ->
        Jido.Instance.Wake.complete(data.jido, data.agent_address, data.active.turn_id)
        ReplyGate.done(data.active.requester)
        TraceContext.clear()
        idle_transition(%{data | active: nil})
    end
  end

  defp record_outcome(data, status, stage, committed, count) do
    active = data.active
    outcome = Lifecycle.outcome(active, data.state_version, status, stage, committed, count)

    metadata = %{
      status: AgentServerTelemetry.status(status),
      stage: if(committed, do: :commit, else: :evaluate),
      committed?: committed
    }

    measurements = %{
      state_version_before: active.start_version,
      state_version_after: data.state_version,
      directive_count: count
    }

    AgentServerTelemetry.settle_turn(active.span, metadata, measurements, committed, count)

    data
    |> Map.put(:last_outcome, outcome)
    |> put_in([:active, :outcome], outcome)
  end

  defp complete_terminal(data) do
    Jido.Instance.Wake.complete(data.jido, data.agent_address, data.active.turn_id)

    if handoff_result?(data.active.result) do
      begin_handoff_release(data)
    else
      replies = accepted_reply(data) ++ cancel_replies(data.active, :ok)
      ReplyGate.done(data.active.requester)
      TraceContext.clear()
      next = %{data | active: nil}
      idle_transition(next, replies)
    end
  end

  defp handoff_result?({:handoff, _candidate, %Jido.Instruction{}, _directives}), do: true
  defp handoff_result?(_result), do: false

  defp handoff_turn_id(%{handoff_receipt: %{id: id}}), do: id
  defp handoff_turn_id(_active), do: nil

  defp handoff_predecessor_id(%{handoff_predecessor_id: id}), do: id
  defp handoff_predecessor_id(_active), do: nil

  defp commit_replies(%{active: %{result: result}}) when elem(result, 0) == :handoff, do: []

  defp commit_replies(data),
    do: accepted_reply(data) ++ cancel_replies(data.active, :ok)

  defp accepted_reply(%{active: %{from: nil}}), do: []
  defp accepted_reply(data), do: reply(data.active.from, {:ok, turn_result(data)})
  defp accepted_reply(%{active: %{from: nil}}, _status), do: []
  defp accepted_reply(data, status), do: reply(data.active.from, {:ok, turn_result(data, status)})

  defp turn_result(data, status \\ nil) do
    active = data.active
    status = status || turn_status(active.result)

    %Jido.AgentServer.TurnResult{
      turn_id: active.turn_id,
      agent_address: data.agent_address,
      agent_activation_id: data.agent_activation_id,
      status: status,
      durability:
        cond do
          data.persistence in [nil, false] -> :memory
          status == :uncertain -> :unknown
          true -> :durable
        end,
      agent_revision: data.agent_revision,
      persistence_revision: data.persistence_revision,
      reply: Map.get(active, :reply),
      waits: if(status == :waiting, do: active.waits, else: []),
      effects: if(active.effects == [], do: :none, else: :pending),
      error: turn_error(active.result, status)
    }
  end

  defp completed_retry_result(data, turn_id) do
    %Jido.AgentServer.TurnResult{
      turn_id: turn_id,
      agent_address: data.agent_address,
      agent_activation_id: data.agent_activation_id,
      status: :committed,
      durability: if(data.persistence in [nil, false], do: :memory, else: :durable),
      agent_revision: data.agent_revision,
      persistence_revision: data.persistence_revision,
      reply: nil,
      waits: [],
      effects: :none,
      error: nil
    }
  end

  defp put_resume_result(receipt, %{active: %{resume_input: nil}}, _result, _agent_rev, _persist_rev),
    do: receipt

  defp put_resume_result(receipt, data, result, agent_revision, persistence_revision) do
    {reply_signal, effects} =
      case result do
        result when elem(result, 0) in [:ok, :handoff] ->
          {_candidate, directives} = success_candidate_and_directives(result)
          take_reply(directives)

        _other ->
          {nil, []}
      end

    active = %{data.active | result: result, reply: reply_signal, effects: effects}

    projected =
      turn_result(%{
        data
        | active: active,
          agent_revision: agent_revision,
          persistence_revision: persistence_revision
      })

    Continuation.put_resume_result!(receipt, projected)
  end

  defp turn_status({status, _candidate, _directives}) when status in [:ok, :handoff],
    do: :committed

  defp turn_status({:error, :cancelled}), do: :cancelled
  defp turn_status({:error, :turn_timeout}), do: :timed_out
  defp turn_status({:error, reason}) when reason in [:indeterminate, :uncertain], do: :uncertain

  defp turn_status({:error, {reason, _details}}) when reason in [:indeterminate, :uncertain],
    do: :uncertain

  defp turn_status({:error, _reason}), do: :failed

  defp turn_error({:error, reason}, status)
       when status in [:failed, :cancelled, :timed_out, :uncertain] do
    if Jido.AgentServer.Status.process_neutral?(reason), do: reason, else: log_reason(reason)
  end

  defp turn_error(_result, _status), do: nil

  defp take_reply(directives) do
    {replies, effects} = Enum.split_with(directives, &match?(%Reply{}, &1))

    reply =
      case replies do
        [%Reply{signal: signal}] -> signal
        [] -> nil
      end

    {reply, effects}
  end

  defp prepared_reply(nil, _context), do: nil

  defp prepared_reply(signal, context) do
    case Effects.prepare_reply(signal, context) do
      {:ok, prepared} -> prepared
      {:error, _reason} -> nil
    end
  end

  defp effect_context(data) do
    active = data.active

    %{
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
  end

  defp begin_handoff_release(data) do
    timeout = data.turn_timeout

    cancel_timer(data.active)

    active = %{
      data.active
      | deadline:
          if(timeout == :infinity,
            do: :infinity,
            else: System.monotonic_time(:millisecond) + timeout
          ),
        timer:
          if(timeout == :infinity,
            do: nil,
            else:
              Process.send_after(
                self(),
                {:turn_timeout, data.active.turn_id},
                min(timeout, Lifecycle.max_timeout())
              )
          )
    }

    operation(:release_handoff, %{data | active: active}, fn ->
      release_handoff(%{data | active: active})
    end)
  end

  defp handoff_transition(%{active: %{handoff_receipt: %{status: :released} = receipt}} = data) do
    cancel_timer(data.active)

    pending = %{
      receipt: receipt,
      from: data.active.from,
      requester: data.active.requester,
      active: data.active
    }

    send(self(), {:handoff_successor, receipt.id})
    TraceContext.clear()

    next = %{data | active: nil, pending_handoff: pending}
    {:next_state, :handoff_pending, cancel_idle(next)}
  end

  defp fail_handoff(data, reason), do: abort_turn(:effects, data, reason)

  defp cancel_pending_handoff(data, pending, cancel_from) do
    active = %{pending.active | cancel_waiters: [cancel_from | pending.active.cancel_waiters]}

    data = %{
      data
      | active: active,
        pending_handoff: nil,
        server_turn: if(active.persisted, do: pending.receipt, else: data.server_turn)
    }

    abort_turn(:effects, data, :cancelled)
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

  defp set_admission(data, mode) do
    persist_runtime(data.activation_state, :admission, mode)
    %{data | admission_mode: mode}
  end

  defp control_caller?(from, data) do
    {caller, _} = from

    Lifecycle.reentrant?({:call, from}, data) or Lifecycle.bootstrap_caller?(from, data) or
      Enum.any?([data.parent_effect, data.control], fn operation ->
        operation != nil and operation.task != nil and
          Lifecycle.owned_process?(caller, operation.task.pid, [], 0)
      end)
  end

  defp settled?(data),
    do:
      data.active == nil and data.pending_handoff == nil and data.parent_effect == nil and
        MapSet.size(data.postponed) == 0

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

    if policy == :cancel and data.active != nil and phase not in [:saving, :effects] do
      case abort_turn(phase, data, :cancelled) do
        {:next_state, next_phase, next} -> {:next_state, next_phase, next, progress}
        {:keep_state, next} -> {:keep_state, next, progress}
      end
    else
      # Reject waiting callers now. OTP drains their postponed events on the
      # next phase change; resume waits for that drain before opening admission.
      if kind == :hibernate,
        do: {:next_state, :passivating, data, progress},
        else: {:keep_state, data, progress}
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
            data = data |> set_admission(:quiesced) |> Map.put(:control, nil)

            {:keep_state, data, reply(control.from, {:ok, public_status(:quiesced, data)})}

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
                Lifecycle.save(
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
              do: {:next_state, :hibernating, next},
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
          do: Lifecycle.error(:quiesce_timeout, true),
          else: {:error, :quiesce_timeout}

      replies = reply(data.control.from, result)

      {:keep_state, %{data | control: nil}, replies ++ [{:next_event, :internal, :control_progress}]}
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

      {:next_state, :waiting, data, reply(control.from, Lifecycle.error(reason, safe?))}
    else
      {:keep_state, data, reply(control.from, Lifecycle.error(reason, safe?))}
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
         safe_residency_idle?(data) do
      token = make_ref()
      timer = Process.send_after(self(), {:idle_timeout, token}, data.idle_timeout)
      %{data | idle_timer: {timer, token}}
    else
      data
    end
  end

  defp safe_residency_idle?(data) do
    settled?(data) or
      (data.persistence not in [nil, false] and data.active != nil and
         data.active.worker == nil and data.active.operation == nil and data.active.waits != [])
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

    case register_wakes(data) do
      :ok ->
        durable_write(:durable_wait, data, data.agent, data.server_turn)

      {:error, reason} ->
        stop_durable(data, reason)
    end
  end

  defp enter_waiting(data) do
    data = arm_idle(data)
    result = turn_result(data, :waiting)
    replies = reply(data.active.from, {:ok, result})
    ReplyGate.done(data.active.requester)
    data = data |> put_in([:active, :from], nil) |> put_in([:active, :requester], nil)

    {:next_state, :waiting, data, replies ++ [{:next_event, :internal, :control_progress}]}
  end

  defp register_wakes(%{jido: nil}), do: :ok

  defp register_wakes(data) do
    Jido.Instance.Wake.register(
      data.jido,
      data.agent_address,
      data.active.turn_id,
      data.active.waits
    )
  end

  defp suspended_hibernation?(%{
         control: %{kind: :hibernate},
         active: %{worker: nil, operation: nil, waits: [_ | _]}
       }),
       do: true

  defp suspended_hibernation?(_data), do: false

  defp complete_task(task) do
    Process.demonitor(task.ref, [:flush])
    Process.unlink(task.pid)
    :ok
  end
end
