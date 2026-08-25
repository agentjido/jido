defmodule Jido.Actions.Lifecycle do
  @moduledoc """
  Base actions for agent lifecycle and coordination patterns.

  These actions provide common patterns for:
  - Parent-child communication
  - Process spawning
  - Graceful termination

  ## Usage

      use Jido.Agent,
        name: "coordinator_agent",
        signal_routes: [
          {"work.done", Jido.Actions.Lifecycle.NotifyParent},
          {"spawn.worker", Jido.Actions.Lifecycle.SpawnChild},
          {"shutdown", Jido.Actions.Lifecycle.StopSelf}
        ]
  """

  alias Jido.Agent.Directive
  alias Jido.Signal

  defmodule NotifyParent do
    @moduledoc """
    Emit a signal back to the spawning parent agent.

    Requires the agent to have been spawned via `SpawnAgent` directive
    (which populates `__parent__` in state).

    ## Schema

    - `signal_type` - Signal type to emit (required)
    - `payload` - Signal payload data (default: %{})
    - `source` - Signal source path (default: "/child")

    ## Example

        # Route child completion to this action
        {"work.complete", Jido.Actions.Lifecycle.NotifyParent}

        # Or invoke directly with params
        {Jido.Actions.Lifecycle.NotifyParent, %{signal_type: "child.done", payload: %{result: 42}}}
    """
    use Jido.Action,
      name: "notify_parent",
      description: "Emit a signal back to the parent agent",
      schema:
        Zoi.object(%{
          signal_type: Zoi.string(description: "Signal type to emit to parent"),
          payload: Zoi.map(description: "Signal payload data") |> Zoi.default(%{}),
          source: Zoi.string(description: "Signal source path") |> Zoi.default("/child")
        })

    def run(%{signal_type: type, payload: payload, source: source}, context) do
      signal = Signal.new!(type, payload, source: source)
      directive = Directive.emit_to_parent(context.agent, signal)
      {:ok, %{notified: directive != nil}, List.wrap(directive)}
    end
  end

  defmodule NotifyPid do
    @moduledoc """
    Emit a signal to an arbitrary process by PID.

    ## Schema

    - `target_pid` - PID to send signal to (required)
    - `signal_type` - Signal type to emit (required)
    - `payload` - Signal payload data (default: %{})
    - `source` - Signal source path (default: "/agent")
    - `delivery_mode` - :async (default) or :sync

    ## Example

        {Jido.Actions.Lifecycle.NotifyPid, %{
          target_pid: some_pid,
          signal_type: "result.ready",
          payload: %{data: result}
        }}
    """
    use Jido.Action,
      name: "notify_pid",
      description: "Emit a signal to a specific process",
      schema:
        Zoi.object(%{
          target_pid: Zoi.any(description: "Target process PID"),
          signal_type: Zoi.string(description: "Signal type to emit"),
          payload: Zoi.map(description: "Signal payload data") |> Zoi.default(%{}),
          source: Zoi.string(description: "Signal source path") |> Zoi.default("/agent"),
          delivery_mode:
            Zoi.enum([:async, :sync], description: "Delivery mode") |> Zoi.default(:async)
        })

    def run(
          %{
            target_pid: pid,
            signal_type: type,
            payload: payload,
            source: source,
            delivery_mode: mode
          },
          _context
        )
        when is_pid(pid) do
      signal = Signal.new!(type, payload, source: source)
      directive = Directive.emit_to_pid(signal, pid, delivery_mode: mode)
      {:ok, %{sent_to: pid}, [directive]}
    end

    def run(%{target_pid: pid}, _context) do
      {:error, {:invalid_target_pid, pid}}
    end
  end

  defmodule SpawnChild do
    @moduledoc """
    Spawn a child agent with hierarchy tracking.

    The spawned agent will have a parent reference allowing it to
    use `emit_to_parent/3` to communicate back.

    ## Schema

    - `agent_module` - Agent module to spawn (required)
    - `tag` - Tag for tracking this child (required)
    - `initial_state` - Initial state for the child agent (default: %{})
    - `meta` - Metadata to pass to child (default: %{})
    - `restart` - Restart policy for the child (default: `:transient`)

    ## Example

        {"coordinator.spawn", Jido.Actions.Lifecycle.SpawnChild}

        # With params
        {Jido.Actions.Lifecycle.SpawnChild, %{
          agent_module: MyWorker,
          tag: :worker_1,
          initial_state: %{batch_size: 100},
          restart: :permanent
        }}
    """
    @restart_policies Directive.valid_restart_policies()

    use Jido.Action,
      name: "spawn_child",
      description: "Spawn a child agent with hierarchy tracking",
      schema:
        Zoi.object(%{
          agent_module: Zoi.atom(description: "Agent module to spawn"),
          tag: Zoi.atom(description: "Tag for tracking this child"),
          initial_state: Zoi.map(description: "Initial state for child") |> Zoi.default(%{}),
          meta: Zoi.map(description: "Metadata to pass to child") |> Zoi.default(%{}),
          restart:
            Zoi.enum(@restart_policies, description: "Restart policy for the child")
            |> Zoi.default(:transient)
        })

    def run(
          %{agent_module: mod, tag: tag, initial_state: state, meta: meta, restart: restart},
          _context
        ) do
      opts = if state == %{}, do: %{}, else: %{initial_state: state}
      directive = Directive.spawn_agent(mod, tag, opts: opts, meta: meta, restart: restart)
      {:ok, %{spawning: tag}, [directive]}
    end
  end

  defmodule StopSelf do
    @moduledoc """
    Request graceful termination of the current agent process.

    ## Schema

    - `reason` - Reason for stopping (default: :normal)

    ## Example

        {"shutdown", Jido.Actions.Lifecycle.StopSelf}

        # With custom reason
        {Jido.Actions.Lifecycle.StopSelf, %{reason: :work_complete}}
    """
    use Jido.Action,
      name: "stop_self",
      description: "Request graceful termination of this agent",
      schema:
        Zoi.object(%{
          reason: Zoi.any(description: "Reason for stopping") |> Zoi.default(:normal)
        })

    def run(%{reason: reason}, _context) do
      directive = Directive.stop(reason)
      {:ok, %{stopping: true, reason: reason}, [directive]}
    end
  end

  defmodule StopChild do
    @moduledoc """
    Request graceful termination of a tracked child agent.

    ## Schema

    - `tag` - Tag of the child to stop (required)
    - `reason` - Reason for stopping (default: :normal)

    ## Example

        {"coordinator.stop_worker", Jido.Actions.Lifecycle.StopChild}

        {Jido.Actions.Lifecycle.StopChild, %{tag: :worker_1, reason: :shutdown}}
    """
    use Jido.Action,
      name: "stop_child",
      description: "Request graceful termination of a child agent",
      schema:
        Zoi.object(%{
          tag: Zoi.atom(description: "Tag of child to stop"),
          reason: Zoi.any(description: "Reason for stopping") |> Zoi.default(:normal)
        })

    def run(%{tag: tag, reason: reason}, _context) do
      directive = Directive.stop_child(tag, reason)
      {:ok, %{stopping_child: tag, reason: reason}, [directive]}
    end
  end
end
