defmodule Jido.Await do
  @moduledoc """
  Synchronous helpers for waiting on Jido agents from non-agent code.

  This module provides utilities for HTTP controllers, CLI tools, and tests
  that need to synchronously wait for agents to complete. Agents signal
  completion via state, not process death.

  ## Completion Convention

  Agents signal completion by setting a terminal status in their state:

      agent = put_in(agent.state.status, :completed)
      agent = put_in(agent.state.last_answer, result)

  The `completion/3` function uses event-driven waiting via `AgentServer.await_completion/2`,
  blocking until the agent reaches a terminal state without polling.

  ## Examples

      # Wait for a single agent
      {:ok, pid} = Jido.start_agent(jido, MyAgent)
      AgentServer.cast(pid, some_signal)
      {:ok, %{status: :completed, result: answer}} = Jido.Await.completion(pid, 10_000)

      # Wait for all agents to complete
      {:ok, results} = Jido.Await.all([pid1, pid2, pid3], 30_000)

      # Wait for the first agent to complete
      {:ok, {winner_pid, result}} = Jido.Await.any([pid1, pid2], 10_000)

      # Wait for a specific child of a parent agent
      {:ok, result} = Jido.Await.child(coordinator, :worker_1, 30_000)
  """

  alias Jido.AgentServer
  alias Jido.Runtime.Tasking
  alias Jido.RuntimeDefaults

  @type server :: AgentServer.server()
  @type status :: :completed | :failed | atom()
  @type completion :: %{status: status(), result: any()}
  @system_task_supervisor Jido.SystemTaskSupervisor

  # ---------------------------------------------------------------------------
  # Single Agent Completion
  # ---------------------------------------------------------------------------

  @doc """
  Wait for an agent to reach a terminal status.

  Uses event-driven waiting via GenServer.call - the caller blocks until
  the agent's state transitions to `:completed` or `:failed`, then receives
  the result immediately. No polling is involved.

  ## Options

  - `:status_path` - Path to status field (default: `[:status]`)
  - `:result_path` - Path to result field (default: `[:last_answer]`)
  - `:error_path` - Path to error field (default: `[:error]`)

  ## Returns

  - `{:ok, %{status: :completed, result: any()}}` - Agent completed successfully
  - `{:ok, %{status: :failed, result: any()}}` - Agent failed
  - `{:error, :timeout}` - Timeout reached before completion
  - `{:error, :not_found}` - Agent process not found

  ## Examples

      {:ok, result} = Jido.Await.completion(agent_pid, 10_000)

      # With custom paths for strategy state
      {:ok, result} = Jido.Await.completion(agent_pid, 10_000,
        status_path: [:__strategy__, :status],
        result_path: [:__strategy__, :result]
      )
  """
  @spec completion(server(), non_neg_integer(), Keyword.t()) ::
          {:ok, completion()} | {:error, term()}
  def completion(server, timeout_ms \\ RuntimeDefaults.await_timeout(), opts \\ []) do
    opts = Keyword.put(opts, :timeout, timeout_ms)

    try do
      AgentServer.await_completion(server, opts)
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
    end
  end

  # ---------------------------------------------------------------------------
  # Child Agent Completion
  # ---------------------------------------------------------------------------

  @doc """
  Wait for a specific child of a parent agent to complete.

  First looks up the child by tag in the parent's `children` map,
  then polls the child for completion.

  ## Options

  Same as `completion/3`.

  ## Returns

  - `{:ok, %{status: atom(), result: any()}}` - Child completed
  - `{:error, :timeout}` - Timeout reached
  - `{:error, term()}` - Other error

  ## Examples

      {:ok, coordinator} = Jido.start_agent(jido, CoordinatorAgent)
      AgentServer.cast(coordinator, %Signal{type: "spawn_worker"})
      {:ok, result} = Jido.Await.child(coordinator, :worker_1, 30_000)
  """
  @spec child(server(), term(), non_neg_integer(), Keyword.t()) ::
          {:ok, completion()} | {:error, term()}
  def child(
        parent_server,
        child_tag,
        timeout_ms \\ RuntimeDefaults.await_child_timeout(),
        opts \\ []
      ) do
    deadline = now_ms() + timeout_ms

    with {:ok, child_pid} <- poll_for_child(parent_server, child_tag, deadline, 50) do
      remaining = max(0, deadline - now_ms())
      completion(child_pid, remaining, opts)
    end
  end

  defp poll_for_child(parent_server, child_tag, deadline, poll_interval) do
    if now_ms() > deadline do
      {:error, :timeout}
    else
      case lookup_child_pid(parent_server, child_tag) do
        {:ok, pid} ->
          {:ok, pid}

        {:error, :not_found} ->
          sleep(poll_interval)
          poll_for_child(parent_server, child_tag, deadline, poll_interval)

        {:error, _} = error ->
          error
      end
    end
  end

  defp lookup_child_pid(parent_server, child_tag) do
    case AgentServer.state(parent_server) do
      {:ok, %{children: children}} ->
        case Map.get(children, child_tag) do
          %{pid: pid} when is_pid(pid) -> {:ok, pid}
          _ -> {:error, :not_found}
        end

      {:error, _} = error ->
        error
    end
  end

  # ---------------------------------------------------------------------------
  # Multi-Agent Coordination
  # ---------------------------------------------------------------------------

  @doc """
  Wait for all agents to reach terminal status.

  Spawns concurrent waiters for each agent and collects results.
  Returns when all complete or on first infrastructure error.

  ## Options

  Same as `completion/3`.

  ## Returns

  - `{:ok, %{server => completion()}}` - All agents completed (includes `:failed` status)
  - `{:error, :timeout}` - Timeout reached before all completed
  - `{:error, {server, reason}}` - Infrastructure error for specific server

  ## Examples

      {:ok, results} = Jido.Await.all([pid1, pid2, pid3], 30_000)
      # => %{pid1 => %{status: :completed, result: ...}, ...}
  """
  @spec all([server()], non_neg_integer(), Keyword.t()) ::
          {:ok, %{server() => completion()}} | {:error, :timeout} | {:error, {server(), term()}}
  def all(servers, timeout_ms \\ RuntimeDefaults.await_timeout(), opts \\ [])
  def all([], _timeout_ms, _opts), do: {:ok, %{}}

  def all(servers, timeout_ms, opts) do
    caller = self()
    deadline = now_ms() + timeout_ms

    case start_waiters(servers, caller, deadline, opts) do
      {:ok, waiters} -> collect_all(waiters, %{}, deadline)
      {:error, {server, reason}} -> {:error, {server, reason}}
    end
  end

  defp collect_all(waiters, acc, _deadline) when map_size(waiters) == 0 do
    {:ok, acc}
  end

  defp collect_all(waiters, acc, deadline) do
    remaining = max(0, deadline - now_ms())

    receive do
      {:await_result, ref, server, {:ok, result}} ->
        collect_all(Map.delete(waiters, ref), Map.put(acc, server, result), deadline)

      {:await_result, ref, _server, {:error, :timeout}} ->
        kill_waiters(Map.delete(waiters, ref))
        {:error, :timeout}

      {:await_result, ref, _server, {:error, {:timeout, _diagnostic}}} ->
        kill_waiters(Map.delete(waiters, ref))
        {:error, :timeout}

      {:await_result, ref, server, {:error, reason}} ->
        kill_waiters(Map.delete(waiters, ref))
        {:error, {server, reason}}
    after
      remaining ->
        kill_waiters(waiters)
        {:error, :timeout}
    end
  end

  @doc """
  Wait for any agent to reach terminal status.

  Returns as soon as the first agent completes.

  ## Options

  Same as `completion/3`.

  ## Returns

  - `{:ok, {server, completion()}}` - First agent to complete
  - `{:error, :timeout}` - Timeout reached before any completed
  - `{:error, {server, reason}}` - Infrastructure error

  ## Examples

      {:ok, {winner, result}} = Jido.Await.any([pid1, pid2], 10_000)
  """
  @spec any([server()], non_neg_integer(), Keyword.t()) ::
          {:ok, {server(), completion()}} | {:error, :timeout} | {:error, {server(), term()}}
  def any(servers, timeout_ms \\ RuntimeDefaults.await_timeout(), opts \\ [])
  def any([], _timeout_ms, _opts), do: {:error, :timeout}

  def any(servers, timeout_ms, opts) do
    caller = self()
    deadline = now_ms() + timeout_ms

    case start_waiters(servers, caller, deadline, opts) do
      {:ok, waiters} -> wait_for_any(waiters, deadline)
      {:error, {server, reason}} -> {:error, {server, reason}}
    end
  end

  defp wait_for_any(waiters, deadline) do
    remaining = max(0, deadline - now_ms())

    receive do
      {:await_result, ref, server, {:ok, result}} ->
        kill_waiters(Map.delete(waiters, ref))
        {:ok, {server, result}}

      {:await_result, ref, _server, {:error, :timeout}} ->
        kill_waiters(Map.delete(waiters, ref))
        {:error, :timeout}

      {:await_result, ref, _server, {:error, {:timeout, _diagnostic}}} ->
        kill_waiters(Map.delete(waiters, ref))
        {:error, :timeout}

      {:await_result, ref, server, {:error, reason}} ->
        kill_waiters(Map.delete(waiters, ref))
        {:error, {server, reason}}
    after
      remaining ->
        kill_waiters(waiters)
        {:error, :timeout}
    end
  end

  defp kill_waiters(waiters) do
    Enum.each(waiters, fn {_ref, %{pid: pid}} ->
      Process.exit(pid, :kill)
    end)
  end

  defp start_waiters(servers, caller, deadline, opts) do
    Enum.reduce_while(servers, {:ok, %{}}, fn server, {:ok, waiters} ->
      ref = make_ref()

      case start_waiter(caller, ref, server, deadline, opts) do
        {:ok, pid} ->
          waiter = %{server: server, pid: pid}
          {:cont, {:ok, Map.put(waiters, ref, waiter)}}

        {:error, reason} ->
          kill_waiters(waiters)
          {:halt, {:error, {server, reason}}}
      end
    end)
  end

  defp start_waiter(caller, ref, server, deadline, opts) do
    task =
      fn ->
        remaining = max(0, deadline - now_ms())
        result = completion(server, remaining, opts)
        send(caller, {:await_result, ref, server, result})
      end

    Tasking.start_child(task, candidates: [@system_task_supervisor])
  end

  # ---------------------------------------------------------------------------
  # Utility Functions
  # ---------------------------------------------------------------------------

  @doc """
  Get the PIDs of all children of a parent agent.

  ## Returns

  - `{:ok, %{tag => pid}}` - Map of child tags to PIDs
  - `{:error, term()}` - Error getting parent state

  ## Examples

      {:ok, children} = Jido.Await.get_children(coordinator)
      # => {:ok, %{worker_1: #PID<0.123.0>, worker_2: #PID<0.124.0>}}
  """
  @spec get_children(server()) :: {:ok, %{term() => pid()}} | {:error, term()}
  def get_children(parent_server) do
    case AgentServer.state(parent_server) do
      {:ok, %{children: children}} ->
        pids = Map.new(children, fn {tag, %{pid: pid}} -> {tag, pid} end)
        {:ok, pids}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Get a specific child's PID by tag.

  ## Returns

  - `{:ok, pid}` - Child found
  - `{:error, :child_not_found}` - Child with given tag not found
  - `{:error, term()}` - Error getting parent state

  ## Examples

      {:ok, worker_pid} = Jido.Await.get_child(coordinator, :worker_1)
  """
  @spec get_child(server(), term()) :: {:ok, pid()} | {:error, :child_not_found | term()}
  def get_child(parent_server, child_tag) do
    case AgentServer.state(parent_server) do
      {:ok, %{children: children}} ->
        case Map.get(children, child_tag) do
          %{pid: pid} when is_pid(pid) -> {:ok, pid}
          _ -> {:error, :child_not_found}
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Check if an agent process is alive and responding.

  ## Examples

      if Jido.Await.alive?(agent_pid) do
        # safe to interact
      end
  """
  @spec alive?(server()) :: boolean()
  def alive?(server) do
    case AgentServer.state(server) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Request graceful cancellation of an agent.

  Sends a cancel signal to the agent. The agent decides how to respond
  (e.g., set `state.status = :failed` with `state.error = :cancelled`).

  This is advisory - callers should use `completion/3` to wait for
  the agent to actually reach a terminal state.

  ## Options

  - `:reason` - Cancellation reason (default: `:client_cancelled`)

  ## Examples

      :ok = Jido.Await.cancel(agent_pid)
      {:ok, %{status: :failed}} = Jido.Await.completion(agent_pid, 5_000)
  """
  @spec cancel(server(), Keyword.t()) :: :ok | {:error, term()}
  def cancel(server, opts \\ []) do
    reason = Keyword.get(opts, :reason, :client_cancelled)

    signal = Jido.Signal.new!("jido.agent.cancel", %{reason: reason})
    AgentServer.cast(server, signal)
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp sleep(ms) when ms > 0, do: Process.sleep(ms)
  defp sleep(_), do: :ok
end
