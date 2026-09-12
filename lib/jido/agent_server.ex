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
  alias Jido.AgentServer.{AdmissionDeadline, Options, ParentRef, Runtime}
  alias Jido.Error
  alias Jido.Signal

  @type server :: pid() | atom() | {:global, term()} | {:via, module(), term()}
  @type signal_result :: {:ok, Agent.t()} | {:error, term()}
  @type call_option :: {:timeout, timeout()} | {:context, map() | keyword() | nil}
  @type upgrade_operation :: (-> :ok | {:error, term()})
  @type state_migration :: (Agent.t() -> {:ok, map()} | {:error, term()})

  @call_schema Zoi.object(
                 %{
                   timeout:
                     Zoi.union([Zoi.integer() |> Zoi.min(0), Zoi.literal(:infinity)])
                     |> Zoi.default(5_000),
                   context: Zoi.any() |> Zoi.default(%{})
                 },
                 unrecognized_keys: :error
               )

  @doc """
  Starts one Agent Server linked to the calling process.

  Use `Jido.start_agent/3` for instance-supervised ownership instead.
  """
  @spec start_link(keyword()) :: :gen_statem.start_ret()
  def start_link(opts) when is_list(opts), do: start_link(opts, nil)

  @doc false
  def start_link(opts, startup_reply) when is_list(opts) do
    with {:ok, options} <- Options.new(opts) do
      case server_name(options) do
        nil -> :gen_statem.start_link(Runtime, {options, startup_reply}, [])
        name -> :gen_statem.start_link(name, Runtime, {options, startup_reply}, [])
      end
    end
  end

  @doc """
  Starts one Agent Server under its Jido instance supervisor.

  The Server links to that supervisor. It does not link to the original caller.
  """
  @spec start(keyword()) :: DynamicSupervisor.on_start_child()
  def start(opts) when is_list(opts) do
    case Keyword.get(opts, :jido) do
      jido when is_atom(jido) and not is_nil(jido) ->
        reply = :erlang.alias()
        spec = %{child_spec(opts) | start: {__MODULE__, :start_link, [opts, reply]}}

        try do
          case DynamicSupervisor.start_child(Jido.agent_supervisor_name(jido), spec) do
            {:ok, pid} -> startup_result(pid, reply)
            {:ok, pid, _info} -> startup_result(pid, reply)
            result -> result
          end
        after
          :erlang.unalias(reply)
        end

      _value ->
        {:error, :jido_instance_required}
    end
  end

  @doc "Returns a child specification for one Agent Server."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    id = Keyword.get(opts, :id, make_ref())
    default_restart = if Keyword.get(opts, :jido), do: :transient, else: :temporary
    restart = Keyword.get(opts, :restart, default_restart)

    %{
      id: {__MODULE__, id},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: restart,
      shutdown: 5_000
    }
  end

  @doc """
  Sends one Signal and waits for its commit or failure.

  The third argument accepts a timeout or a keyword list with `:timeout` and
  `:context`. Caller context belongs to this Turn. Jido does not add it to the
  Signal data, committed Agent state, persistence record, or emitted Signals.

  Caller timeout stops waiting. It does not cancel work that already started.
  Use `cancel/2` or `cancel_turn/3` to request cancellation.
  """
  @spec call(server(), Signal.t(), timeout() | [call_option()]) :: signal_result()
  def call(server, signal, timeout_or_opts \\ 5_000)

  def call(server, %Signal{} = signal, opts) when is_list(opts) do
    with {:ok, opts} <- validate_keyword(opts, :call),
         {:ok, options} <- parse_call_options(opts),
         {:ok, context} <- Jido.Agent.Command.normalize_context(options.context) do
      call_with_context(server, signal, options.timeout, context)
    end
  end

  def call(server, %Signal{} = signal, timeout) do
    call_with_context(server, signal, timeout, %{})
  end

  @doc "Sends one asynchronous Signal. Delivery is best effort under overload."
  @spec cast(server(), Signal.t()) :: :ok
  def cast(server, %Signal{} = signal) do
    :gen_statem.cast(server, {:signal, make_ref(), signal})
  end

  @doc "Stops one Agent Server through its normal OTP termination path."
  @spec stop(server(), term(), timeout()) :: :ok
  def stop(server, reason \\ :shutdown, timeout \\ 5_000) do
    :gen_statem.stop(server, normalize_stop_reason(reason), timeout)
  end

  @doc "Returns one declared Plugin's owned field from the complete Agent state map."
  @spec plugin_state(server(), module(), timeout()) :: {:ok, term()} | {:error, term()}
  def plugin_state(server, plugin, timeout \\ 5_000) when is_atom(plugin) do
    :gen_statem.call(server, {:plugin_state, plugin}, timeout)
  end

  @doc "Starts an asynchronous request for one Signal."
  @spec send_request(server(), Signal.t(), timeout()) :: term()
  def send_request(server, %Signal{} = signal, timeout \\ 5_000) do
    :gen_statem.send_request(
      server,
      {:signal, make_ref(), signal, AdmissionDeadline.new(timeout)}
    )
  end

  @doc "Receives the response for `send_request/3`."
  @spec receive_response(term(), timeout()) :: term()
  def receive_response(request_id, timeout \\ 5_000) do
    :gen_statem.receive_response(request_id, timeout)
  end

  @doc "Returns the current committed Agent value."
  @spec agent(server(), timeout()) :: Agent.t()
  def agent(server, timeout \\ 5_000), do: :gen_statem.call(server, :agent, timeout)

  @doc """
  Returns a narrow view of current Agent Server work.

  The result contains the public phase, Agent ID, commit revision, admission
  counts, lifecycle information, and a bounded active-Turn summary.
  """
  @spec status(server(), timeout()) :: map()
  def status(server, timeout \\ 5_000), do: :gen_statem.call(server, :status, timeout)

  @doc "Waits until Agent runtime children are ready."
  @spec await_ready(server(), timeout()) :: :ok | {:error, term()}
  def await_ready(server, timeout \\ 5_000) do
    :gen_statem.call(server, :await_ready, timeout)
  catch
    :exit, reason -> {:error, normalize_ready_error(reason)}
  end

  @doc "Cancels the active executable Turn."
  @spec cancel(server(), timeout()) :: :ok | {:error, term()}
  def cancel(server, timeout \\ 5_000), do: :gen_statem.call(server, :cancel, timeout)

  @doc "Cancels the active executable Turn only when its stable ID matches."
  @spec cancel_turn(server(), String.t(), timeout()) :: :ok | {:error, term()}
  def cancel_turn(server, turn_id, timeout \\ 5_000) when is_binary(turn_id) do
    :gen_statem.call(server, {:cancel, turn_id}, timeout)
  end

  @doc "Enables or disables the bounded runtime event buffer for one Agent."
  @spec set_debug(server(), boolean(), timeout()) :: :ok
  def set_debug(server, enabled, timeout \\ 5_000) when is_boolean(enabled) do
    :gen_statem.call(server, {:set_debug, enabled}, timeout)
  end

  @doc """
  Returns recent Agent runtime events in newest-first order.

  Use `:limit` to request fewer events than the configured maximum. This
  function returns `{:error, :debug_not_enabled}` when the buffer is off.
  """
  @spec recent_events(server(), keyword(), timeout()) :: {:ok, [map()]} | {:error, term()}
  def recent_events(server, opts \\ [], timeout \\ 5_000) when is_list(opts) do
    :gen_statem.call(server, {:recent_events, opts}, timeout)
  end

  @doc "Returns the PID for an Agent ID in one Registry."
  @spec whereis(module(), String.t(), keyword()) :: pid() | nil
  def whereis(registry, id, opts \\ []) when is_atom(registry) and is_binary(id) do
    key = registry_key(id, Keyword.get(opts, :partition))

    case Registry.lookup(registry, key) do
      [{pid, :ready}] -> if Process.alive?(pid), do: pid
      [{_pid, _status}] -> nil
      [] -> nil
    end
  end

  @doc "Returns a Registry via tuple for an Agent ID."
  @spec via_tuple(String.t(), module(), keyword()) :: {:via, Registry, {module(), term()}}
  def via_tuple(id, registry, opts \\ []) when is_binary(id) and is_atom(registry) do
    {:via, Registry, {registry, registry_key(id, Keyword.get(opts, :partition))}}
  end

  @doc """
  Returns true when the Agent Server is alive.

  A remote check has a one-second limit. False means that liveness was not
  confirmed. It does not prove that the process stopped during a network fault.
  """
  @spec alive?(server()) :: boolean()
  def alive?(server) when is_pid(server) and node(server) == node(), do: Process.alive?(server)

  def alive?(server) when is_pid(server) do
    :erpc.call(node(server), Process, :alive?, [server], 1_000)
  catch
    _kind, _reason -> false
  end

  def alive?(server) do
    case GenServer.whereis(server) do
      pid when is_pid(pid) -> alive?(pid)
      _value -> false
    end
  end

  @doc "Attaches an owner process and prevents idle hibernation."
  @spec attach(server(), pid(), timeout()) :: :ok | {:error, term()}
  def attach(server, owner_pid \\ self(), timeout \\ 5_000) when is_pid(owner_pid) do
    :gen_statem.call(server, {:attach, owner_pid}, timeout)
  end

  @doc "Detaches an owner process. The idle timer starts after the last detach."
  @spec detach(server(), pid(), timeout()) :: :ok | {:error, term()}
  def detach(server, owner_pid \\ self(), timeout \\ 5_000) when is_pid(owner_pid) do
    :gen_statem.call(server, {:detach, owner_pid}, timeout)
  end

  @doc "Resets the idle timer without attaching an owner process."
  @spec touch(server()) :: :ok
  def touch(server), do: :gen_statem.cast(server, :touch)

  @doc false
  @spec adopt_parent(server(), ParentRef.t()) :: {:ok, map()} | {:error, term()}
  def adopt_parent(server, %ParentRef{} = parent) do
    with {:ok, parent} <- ParentRef.new(parent) do
      :gen_statem.call(server, {:adopt_parent, parent})
    end
  end

  @doc false
  def creation_info(server) do
    {:ok, :gen_statem.call(server, :creation_info, 1_000)}
  catch
    :exit, reason -> {:uncertain, {:child_identity_unavailable, reason}}
  end

  @doc "Adopts one orphaned Agent as a tracked child."
  @spec adopt_child(server(), pid() | String.t(), term(), map()) :: :ok | {:error, term()}
  def adopt_child(server, child, tag, meta \\ %{}) do
    :gen_statem.call(server, {:adopt_child, child, tag, meta})
  end

  @doc "Stops one tracked child Agent."
  @spec stop_child(server(), term(), term()) :: :ok | {:error, term()}
  def stop_child(server, tag, reason \\ :normal) do
    :gen_statem.call(server, {:stop_child, tag, reason})
  end

  @doc "Returns a public view of tracked Agent and Plugin children."
  @spec children(server(), timeout()) :: map()
  def children(server, timeout \\ 5_000), do: :gen_statem.call(server, :children, timeout)

  @doc """
  Returns the committed Agent and its commit revision as `:state_version`.

  Each successful Turn increases the revision once. A failure before commit
  preserves the state and revision. A Directive failure does not undo a commit.
  """
  @spec snapshot(server(), timeout()) :: map()
  def snapshot(server, timeout \\ 5_000), do: :gen_statem.call(server, :snapshot, timeout)

  @doc """
  Runs one upgrade operation after the Agent Server becomes idle.

  Signals that arrive after the request stay behind it in OTP event order. The
  operation must return `:ok` or `{:error, reason}`.
  """
  @spec upgrade(server(), upgrade_operation()) :: :ok | {:error, term()}
  def upgrade(server, operation), do: upgrade(server, operation, 5_000)

  @spec upgrade(server(), upgrade_operation(), timeout()) :: :ok | {:error, term()}
  def upgrade(server, operation, timeout) when is_function(operation, 0) do
    :gen_statem.call(server, {:upgrade_operation, operation}, timeout)
  end

  @doc """
  Replaces the live Agent definition with validated migrated state.

  The migration runs after the Server becomes idle. The target must keep the
  same Agent identity and Plugin declarations. A successful change writes the
  required checkpoint before the new Agent becomes visible.
  """
  @spec upgrade(server(), module(), state_migration()) ::
          {:ok, Agent.t()} | {:error, term()}
  def upgrade(server, target_module, migration),
    do: upgrade(server, target_module, migration, 5_000)

  @spec upgrade(server(), module(), state_migration(), timeout()) ::
          {:ok, Agent.t()} | {:error, term()}
  def upgrade(server, target_module, migration, timeout)
      when is_atom(target_module) and is_function(migration, 1) do
    :gen_statem.call(server, {:upgrade_definition, target_module, migration}, timeout)
  end

  @doc "Persists and stops one Agent Server after it becomes idle."
  @spec hibernate(server(), keyword()) :: :ok | {:error, term()}
  def hibernate(server, opts \\ []) when is_list(opts) do
    {timeout, opts} = Keyword.pop(opts, :timeout, 5_000)

    case resolve_server_pid(server) do
      pid when is_pid(pid) -> hibernate_pid(pid, opts, timeout)
      nil -> {:error, :not_running}
    end
  end

  defp parse_call_options(opts) do
    case Zoi.parse(@call_schema, Map.new(opts)) do
      {:ok, options} ->
        {:ok, options}

      {:error, issues} ->
        {:error,
         Error.validation_error("Invalid Agent Server call options", details: %{issues: issues})}
    end
  end

  defp call_with_context(server, signal, timeout, context) do
    :gen_statem.call(
      server,
      {:signal, make_ref(), signal, AdmissionDeadline.new(timeout), context},
      timeout
    )
  end

  defp validate_keyword(value, _field) when is_list(value) and value == [], do: {:ok, value}

  defp validate_keyword(value, field) when is_list(value) do
    if Keyword.keyword?(value) do
      {:ok, value}
    else
      {:error, Error.validation_error("#{field} must be a keyword list")}
    end
  end

  defp hibernate_pid(pid, opts, timeout) do
    ref = Process.monitor(pid)

    try do
      case :gen_statem.call(pid, {:hibernate, opts}, timeout) do
        :ok ->
          receive do
            {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
          after
            timeout -> {:error, :timeout}
          end

        error ->
          error
      end
    catch
      :exit, reason -> {:error, normalize_hibernate_error(reason)}
    after
      Process.demonitor(ref, [:flush])
    end
  end

  defp resolve_server_pid(server) do
    GenServer.whereis(server)
  rescue
    _error -> nil
  catch
    _kind, _reason -> nil
  end

  defp startup_result(pid, reply) do
    monitor = Process.monitor(pid)

    try do
      receive do
        {^reply, :ok} ->
          {:ok, pid}

        {^reply, {:error, reason}} ->
          {:error, reason}

        {:DOWN, ^monitor, :process, ^pid, reason} ->
          receive do
            {^reply, :ok} -> {:ok, pid}
            {^reply, {:error, _reason} = error} -> error
          after
            0 -> {:error, normalize_startup_error(reason)}
          end
      after
        5_000 ->
          if Process.alive?(pid), do: Process.exit(pid, :shutdown)
          {:error, :timeout}
      end
    after
      Process.demonitor(monitor, [:flush])
    end
  end

  defp server_name(%Options{name: name}) when not is_nil(name), do: normalize_name(name)

  defp server_name(%Options{register: true, registry: registry, agent: agent} = opts)
       when is_atom(registry) and not is_nil(registry) do
    via_tuple(agent.id, registry, partition: opts.partition)
  end

  defp server_name(%Options{}), do: nil

  defp registry_key(id, partition), do: {:agent, Jido.partition_key(id, partition)}

  defp normalize_name(name) when is_atom(name), do: {:local, name}
  defp normalize_name({:global, _term} = name), do: name
  defp normalize_name({:via, _module, _term} = name), do: name

  defp normalize_name(name) do
    raise ArgumentError,
          "Agent Server name must be an atom, :global tuple, or :via tuple, got: #{inspect(name)}"
  end

  defp normalize_stop_reason(:normal), do: :normal
  defp normalize_stop_reason(:shutdown), do: :shutdown
  defp normalize_stop_reason({:shutdown, _reason} = reason), do: reason
  defp normalize_stop_reason(reason), do: {:shutdown, reason}

  defp normalize_startup_error({:shutdown, reason}), do: reason
  defp normalize_startup_error(:noproc), do: :not_running
  defp normalize_startup_error(reason), do: reason

  defp normalize_ready_error(
         {{:shutdown, {:bootstrap_failed, reason}}, {:gen_statem, :call, _details}}
       ),
       do: {:bootstrap_failed, reason}

  defp normalize_ready_error({:timeout, {:gen_statem, :call, _details}}), do: :timeout
  defp normalize_ready_error({:noproc, {:gen_statem, :call, _details}}), do: :not_running
  defp normalize_ready_error(reason), do: reason

  defp normalize_hibernate_error({:timeout, {:gen_statem, :call, _details}}), do: :timeout
  defp normalize_hibernate_error({:noproc, {:gen_statem, :call, _details}}), do: :not_running
  defp normalize_hibernate_error(:noproc), do: :not_running
  defp normalize_hibernate_error(reason), do: reason
end
