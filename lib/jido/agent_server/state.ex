defmodule Jido.AgentServer.State do
  @moduledoc """
  Internal state for AgentServer GenServer.

  > #### Internal Module {: .warning}
  > This module is internal to the AgentServer implementation. Its API may
  > change without notice. Use `Jido.AgentServer.state/1` to retrieve state.

  This struct holds all runtime state for an agent instance including
  the agent itself, directive queue, hierarchy tracking, and configuration.
  """

  require Logger

  alias Jido.AgentServer.{ChildInfo, Options, ParentRef}
  alias Jido.AgentServer.State.Lifecycle, as: LifecycleState

  @type status :: :initializing | :idle | :processing | :stopping

  @schema Zoi.struct(
            __MODULE__,
            %{
              # Core identity
              id: Zoi.string(description: "Instance ID"),
              agent_module: Zoi.atom(description: "Agent module"),
              agent: Zoi.any(description: "The Jido.Agent struct"),

              # Status and processing
              status:
                Zoi.atom(description: "Current server status") |> Zoi.default(:initializing),
              processing:
                Zoi.boolean(description: "Whether currently processing directives")
                |> Zoi.default(false),
              queue:
                Zoi.any(description: "Directive queue (:queue.queue())")
                |> Zoi.default(:queue.new()),
              signal_call_inflight:
                Zoi.any(description: "In-flight synchronous signal call context")
                |> Zoi.optional(),
              signal_call_queue:
                Zoi.any(description: "Queued synchronous signal call requests")
                |> Zoi.default(:queue.new()),
              deferred_async_signals:
                Zoi.any(description: "Async signals buffered while sync call is in-flight")
                |> Zoi.default(:queue.new()),

              # Hierarchy
              parent: Zoi.any(description: "Parent reference") |> Zoi.optional(),
              orphaned_from:
                Zoi.any(description: "Former parent reference after orphaning") |> Zoi.optional(),
              children: Zoi.map(description: "Map of tag => ChildInfo") |> Zoi.default(%{}),
              on_parent_death:
                Zoi.atom(description: "Behavior on parent death") |> Zoi.default(:stop),

              # Cron jobs
              cron_jobs:
                Zoi.map(description: "Map of job_id => scheduler job name") |> Zoi.default(%{}),
              cron_monitors:
                Zoi.map(description: "Map of job_id => monitor_ref for cron jobs")
                |> Zoi.default(%{}),
              cron_monitor_refs:
                Zoi.map(description: "Map of monitor_ref => job_id for cron jobs")
                |> Zoi.default(%{}),
              cron_restart_attempts:
                Zoi.map(description: "Map of job_id => restart attempt count for cron jobs")
                |> Zoi.default(%{}),
              cron_restart_timers:
                Zoi.map(description: "Map of job_id => timer_ref for cron restarts")
                |> Zoi.default(%{}),
              cron_restart_timer_refs:
                Zoi.map(description: "Map of timer_ref => job_id for cron restarts")
                |> Zoi.default(%{}),
              cron_specs:
                Zoi.map(description: "Map of job_id => durable cron registration spec")
                |> Zoi.default(%{}),
              cron_runtime_specs:
                Zoi.map(description: "Map of job_id => runtime cron restart spec")
                |> Zoi.default(%{}),
              skip_schedules:
                Zoi.boolean(description: "Skip registering plugin schedules")
                |> Zoi.default(false),
              restored_from_storage:
                Zoi.boolean(description: "Whether the startup agent was already thawed")
                |> Zoi.default(false),

              # Configuration
              jido: Zoi.atom(description: "Jido instance name (required)"),
              partition:
                Zoi.any(description: "Logical partition within the Jido instance")
                |> Zoi.optional(),
              default_dispatch: Zoi.any(description: "Default dispatch config") |> Zoi.optional(),
              error_policy:
                Zoi.any(description: "Error handling policy") |> Zoi.default(:log_only),
              max_queue_size: Zoi.integer(description: "Max queue size") |> Zoi.default(10_000),
              registry: Zoi.atom(description: "Registry module"),
              spawn_fun: Zoi.any(description: "Custom spawn function") |> Zoi.optional(),

              # Routing
              signal_router:
                Zoi.any(description: "Jido.Signal.Router for signal routing")
                |> Zoi.optional(),

              # Observability
              error_count:
                Zoi.integer(description: "Count of errors for max_errors policy")
                |> Zoi.default(0),
              metrics: Zoi.map(description: "Runtime metrics") |> Zoi.default(%{}),
              completion_waiters:
                Zoi.map(description: "Map of ref => waiter for completion notifications")
                |> Zoi.default(%{}),

              # Lifecycle (InstanceManager integration: attachment tracking, idle timeout, storage)
              lifecycle: Zoi.any(description: "Lifecycle state (State.Lifecycle.t())"),

              # Debug mode
              debug:
                Zoi.boolean(description: "Whether debug mode is enabled") |> Zoi.default(false),
              debug_events:
                Zoi.list(Zoi.any(), description: "Ring buffer of debug events (max 500)")
                |> Zoi.default([]),
              debug_max_events:
                Zoi.integer(description: "Max debug events in ring buffer")
                |> Zoi.default(500)
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc """
  Creates a new State from validated Options, agent module, and agent struct.

  If a parent reference is provided, it's injected into the agent's state
  as `agent.state.__parent__` so agents can use `Directive.emit_to_parent/3`.
  """
  @spec from_options(Options.t(), module(), struct()) :: {:ok, t()} | {:error, term()}
  def from_options(%Options{} = opts, agent_module, agent) do
    agent = inject_runtime_refs(agent, opts.partition, opts.parent, nil)
    {agent, staged_cron_specs} = Jido.Scheduler.extract_staged_cron_specs(agent)

    {restored_cron_specs, invalid_cron_specs} =
      Jido.Scheduler.classify_cron_specs(staged_cron_specs)

    Enum.each(invalid_cron_specs, fn {job_id, spec, reason} ->
      Logger.error(
        "AgentServer #{opts.id} dropped malformed persisted cron spec #{inspect(job_id)}: #{inspect(spec)} (#{inspect(reason)})"
      )
    end)

    lifecycle_opts = [
      lifecycle_mod: opts.lifecycle_mod,
      pool: opts.pool,
      pool_key: opts.pool_key,
      idle_timeout: opts.idle_timeout,
      storage: opts.storage
    ]

    with {:ok, lifecycle} <- LifecycleState.new(lifecycle_opts) do
      attrs = %{
        id: opts.id,
        agent_module: agent_module,
        agent: agent,
        status: :initializing,
        processing: false,
        queue: :queue.new(),
        signal_call_inflight: nil,
        signal_call_queue: :queue.new(),
        deferred_async_signals: :queue.new(),
        parent: opts.parent,
        orphaned_from: nil,
        children: %{},
        on_parent_death: opts.on_parent_death,
        jido: opts.jido,
        partition: opts.partition,
        default_dispatch: opts.default_dispatch,
        error_policy: opts.error_policy,
        max_queue_size: opts.max_queue_size,
        registry: opts.registry,
        spawn_fun: opts.spawn_fun,
        cron_jobs: %{},
        cron_monitors: %{},
        cron_monitor_refs: %{},
        cron_restart_attempts: %{},
        cron_restart_timers: %{},
        cron_restart_timer_refs: %{},
        cron_specs: restored_cron_specs,
        cron_runtime_specs: %{},
        skip_schedules: opts.skip_schedules,
        restored_from_storage: opts.restored_from_storage,
        error_count: 0,
        metrics: %{},
        completion_waiters: %{},
        lifecycle: lifecycle,
        debug: opts.debug,
        debug_events: [],
        debug_max_events: Jido.Observe.Config.debug_max_events(opts.jido)
      }

      Zoi.parse(@schema, attrs)
    end
  end

  defp inject_runtime_refs(agent, partition, parent, orphaned_from) do
    %{agent | state: put_runtime_refs(agent.state, partition, parent, orphaned_from)}
  end

  @doc """
  Attaches a parent reference to the runtime and agent state.
  """
  @spec attach_parent(t(), ParentRef.t()) :: t()
  def attach_parent(%__MODULE__{} = state, %ParentRef{} = parent) do
    %{
      state
      | parent: parent,
        orphaned_from: nil,
        agent: inject_runtime_refs(state.agent, state.partition, parent, nil)
    }
  end

  @doc """
  Transitions the runtime into an orphaned state, preserving the former parent.
  """
  @spec orphan_parent(t()) :: t()
  def orphan_parent(%__MODULE__{parent: %ParentRef{} = parent} = state) do
    %{
      state
      | parent: nil,
        orphaned_from: parent,
        agent: inject_runtime_refs(state.agent, state.partition, nil, parent)
    }
  end

  def orphan_parent(%__MODULE__{} = state) do
    %{
      state
      | parent: nil,
        orphaned_from: nil,
        agent: inject_runtime_refs(state.agent, state.partition, nil, nil)
    }
  end

  @doc """
  Updates the agent in state.
  """
  @spec update_agent(t(), struct()) :: t()
  def update_agent(%__MODULE__{} = state, agent) do
    %{
      state
      | agent: inject_runtime_refs(agent, state.partition, state.parent, state.orphaned_from)
    }
  end

  @doc """
  Sets the status.
  """
  @spec set_status(t(), status()) :: t()
  def set_status(%__MODULE__{} = state, status)
      when status in [:initializing, :idle, :processing, :stopping] do
    %{state | status: status}
  end

  @doc """
  Enqueues a directive with its triggering signal for later execution.
  """
  @spec enqueue(t(), Jido.Signal.t(), struct()) :: {:ok, t()} | {:error, :queue_overflow}
  def enqueue(%__MODULE__{queue: queue, max_queue_size: max} = state, signal, directive) do
    if :queue.len(queue) >= max do
      {:error, :queue_overflow}
    else
      {:ok, %{state | queue: :queue.in({signal, directive}, queue)}}
    end
  end

  @doc """
  Enqueues multiple directives from a single signal.
  """
  @spec enqueue_all(t(), Jido.Signal.t(), [struct()]) :: {:ok, t()} | {:error, :queue_overflow}
  def enqueue_all(state, _signal, []), do: {:ok, state}

  def enqueue_all(%__MODULE__{} = state, signal, [directive | rest]) do
    case enqueue(state, signal, directive) do
      {:ok, new_state} -> enqueue_all(new_state, signal, rest)
      error -> error
    end
  end

  @doc """
  Dequeues the next directive for processing.
  """
  @spec dequeue(t()) :: {{:value, {Jido.Signal.t(), struct()}}, t()} | {:empty, t()}
  def dequeue(%__MODULE__{queue: queue} = state) do
    case :queue.out(queue) do
      {{:value, item}, new_queue} ->
        {{:value, item}, %{state | queue: new_queue}}

      {:empty, _} ->
        {:empty, state}
    end
  end

  @doc """
  Returns the current queue length.
  """
  @spec queue_length(t()) :: non_neg_integer()
  def queue_length(%__MODULE__{queue: queue}) do
    :queue.len(queue)
  end

  @doc """
  Checks if the queue is empty.
  """
  @spec queue_empty?(t()) :: boolean()
  def queue_empty?(%__MODULE__{queue: queue}) do
    :queue.is_empty(queue)
  end

  @doc """
  Adds a child to the children map.
  """
  @spec add_child(t(), term(), ChildInfo.t()) :: t()
  def add_child(%__MODULE__{children: children} = state, tag, %ChildInfo{} = child) do
    %{state | children: Map.put(children, tag, child)}
  end

  @doc """
  Removes a child by tag.
  """
  @spec remove_child(t(), term()) :: t()
  def remove_child(%__MODULE__{children: children} = state, tag) do
    %{state | children: Map.delete(children, tag)}
  end

  @doc """
  Removes a child by PID.
  """
  @spec remove_child_by_pid(t(), pid()) :: {term() | nil, t()}
  def remove_child_by_pid(%__MODULE__{children: children} = state, pid) do
    case Enum.find(children, fn {_tag, child} -> child.pid == pid end) do
      {tag, _child} ->
        {tag, %{state | children: Map.delete(children, tag)}}

      nil ->
        {nil, state}
    end
  end

  @doc """
  Gets a child by tag.
  """
  @spec get_child(t(), term()) :: ChildInfo.t() | nil
  def get_child(%__MODULE__{children: children}, tag) do
    Map.get(children, tag)
  end

  defp put_runtime_refs(agent_state, partition, parent, orphaned_from) do
    agent_state
    |> maybe_put_state_key(:__partition__, partition)
    |> maybe_put_state_key(:__parent__, parent)
    |> maybe_put_state_key(:__orphaned_from__, orphaned_from)
  end

  defp maybe_put_state_key(state, key, nil), do: Map.delete(state, key)
  defp maybe_put_state_key(state, key, value), do: Map.put(state, key, value)

  @doc """
  Increments the error count.
  """
  @spec increment_error_count(t()) :: t()
  def increment_error_count(%__MODULE__{error_count: count} = state) do
    %{state | error_count: count + 1}
  end

  @doc """
  Records a debug event if debug mode is enabled.

  Events are stored in a ring buffer (max 500 entries).
  Each event includes a monotonic timestamp for relative timing.
  """
  @spec record_debug_event(t(), atom(), map()) :: t()
  def record_debug_event(%__MODULE__{} = state, type, data) do
    if state.debug || Jido.Debug.enabled?(state.jido) do
      event = %{
        at: System.monotonic_time(:millisecond),
        type: type,
        data: data,
        jido_instance: state.jido,
        jido_partition: state.partition
      }

      new_events = Enum.take([event | state.debug_events], state.debug_max_events)
      %{state | debug_events: new_events}
    else
      state
    end
  end

  @doc """
  Returns recent debug events, newest first.

  ## Options

  - `:limit` - Maximum number of events to return (default: all)
  """
  @spec get_debug_events(t(), keyword()) :: [map()]
  def get_debug_events(%__MODULE__{debug_events: events}, opts \\ []) do
    limit = Keyword.get(opts, :limit)

    case limit do
      nil -> events
      n when is_integer(n) and n > 0 -> Enum.take(events, n)
      _ -> events
    end
  end

  @doc """
  Enables or disables debug mode at runtime.
  """
  @spec set_debug(t(), boolean()) :: t()
  def set_debug(%__MODULE__{} = state, enabled) when is_boolean(enabled) do
    %{state | debug: enabled}
  end
end
