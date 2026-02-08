defmodule Jido.Agent.WorkerPool do
  @moduledoc """
  Poolboy-based checkout/checkin worker pool for pre-warmed Jido agents.

  WorkerPool provides a transaction-style API for working with pools of pre-initialized
  agents using poolboy's checkout/checkin pattern. This is useful when agent initialization
  is expensive (loading models, establishing connections, etc.) and you want to reuse
  agents across requests.

  ## Configuration

  Pools are configured per Jido instance via the `:agent_pools` option:

      children = [
        {Jido,
         name: MyApp.Jido,
         agent_pools: [
           {:fast_search, MyApp.Agents.SearchAgent, size: 8, max_overflow: 4},
           {:planner, MyApp.Agents.PlannerAgent, size: 4, strategy: :fifo}
         ]}
      ]

  ## Pool Options

  - `:size` - Fixed number of pre-warmed agents (default: 5)
  - `:max_overflow` - Max temporary workers when pool is exhausted (default: 0)
  - `:strategy` - `:lifo` (default) or `:fifo` for agent checkout order
  - `:worker_opts` - Options passed to `Jido.AgentServer.start_link/1`

  ## Usage

  The recommended approach is to use `with_agent/4` or `call/4`:

      # Simple call - handles checkout/checkin automatically
      {:ok, result} = Jido.Agent.WorkerPool.call(MyApp.Jido, :fast_search, signal)

      # Transaction-style for multiple operations
      Jido.Agent.WorkerPool.with_agent(MyApp.Jido, :fast_search, fn pid ->
        Jido.AgentServer.call(pid, signal1)
        Jido.AgentServer.call(pid, signal2)
      end)

  ## State Semantics

  Pooled agents are **long-lived stateful workers**. State persists across checkouts
  unless the agent crashes (which triggers a restart with fresh state). If you need
  per-request isolation, design your agent to accept request-specific data via signals
  rather than storing it in agent state.

  ## Low-Level API

  For advanced use cases, `checkout/3` and `checkin/3` are available but not recommended:

      pid = Jido.Agent.WorkerPool.checkout(MyApp.Jido, :fast_search)
      try do
        # work with pid
      after
        Jido.Agent.WorkerPool.checkin(MyApp.Jido, :fast_search, pid)
      end
  """

  alias Jido.RuntimeDefaults

  @type instance :: atom()
  @type pool_name :: atom()

  @doc """
  Executes a function with a pooled agent, handling checkout/checkin automatically.

  This is the safest way to use pooled agents.

  ## Options

  - `:timeout` - Checkout timeout in milliseconds (default: 5000)

  ## Examples

      Jido.Agent.WorkerPool.with_agent(MyApp.Jido, :fast_search, fn pid ->
        Jido.AgentServer.call(pid, signal)
      end)

      # With timeout
      Jido.Agent.WorkerPool.with_agent(MyApp.Jido, :fast_search, fn pid ->
        Jido.AgentServer.call(pid, signal)
      end, timeout: 10_000)
  """
  @spec with_agent(instance(), pool_name(), (pid() -> result), keyword()) :: result
        when result: term()
  def with_agent(jido_instance, pool_name, fun, opts \\ []) when is_function(fun, 1) do
    timeout = Keyword.get(opts, :timeout, RuntimeDefaults.worker_pool_timeout())
    pool = Jido.agent_pool_name(jido_instance, pool_name)

    :poolboy.transaction(
      pool,
      fn pid ->
        fun.(pid)
      end,
      timeout
    )
  end

  @doc """
  Sends a signal to a pooled agent and waits for completion.

  This is a convenience wrapper around `with_agent/4` that sends a single signal.

  ## Options

  - `:timeout` - Checkout timeout in milliseconds (default: 5000)
  - Additional options are passed to `Jido.AgentServer.call/3`

  ## Examples

      {:ok, result} = Jido.Agent.WorkerPool.call(MyApp.Jido, :fast_search, signal)
      {:ok, result} = Jido.Agent.WorkerPool.call(MyApp.Jido, :fast_search, signal, timeout: 10_000)
  """
  @spec call(instance(), pool_name(), term(), keyword()) :: term()
  def call(jido_instance, pool_name, signal, opts \\ []) do
    call_timeout = Keyword.get(opts, :call_timeout, RuntimeDefaults.worker_pool_call_timeout())

    with_agent(
      jido_instance,
      pool_name,
      fn pid ->
        Jido.AgentServer.call(pid, signal, call_timeout)
      end,
      opts
    )
  end

  @doc """
  Sends an async signal to a pooled agent.

  Note: The agent is checked back in immediately after casting.
  Use `with_agent/4` if you need to wait for results.

  ## Examples

      :ok = Jido.Agent.WorkerPool.cast(MyApp.Jido, :fast_search, signal)
  """
  @spec cast(instance(), pool_name(), term(), keyword()) :: :ok
  def cast(jido_instance, pool_name, signal, opts \\ []) do
    with_agent(
      jido_instance,
      pool_name,
      fn pid ->
        Jido.AgentServer.cast(pid, signal)
      end,
      opts
    )

    :ok
  end

  @doc """
  Low-level checkout of an agent from the pool.

  **Warning**: You MUST call `checkin/3` when done, even if an error occurs.
  Prefer `with_agent/4` which handles this automatically.

  ## Options

  - `:timeout` - Checkout timeout in milliseconds (default: 5000)
  - `:block` - Whether to block waiting for an available worker (default: true)

  ## Examples

      pid = Jido.Agent.WorkerPool.checkout(MyApp.Jido, :fast_search)
      try do
        Jido.AgentServer.call(pid, signal)
      after
        Jido.Agent.WorkerPool.checkin(MyApp.Jido, :fast_search, pid)
      end
  """
  @spec checkout(instance(), pool_name(), keyword()) :: pid()
  def checkout(jido_instance, pool_name, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, RuntimeDefaults.worker_pool_timeout())
    block = Keyword.get(opts, :block, true)
    pool = Jido.agent_pool_name(jido_instance, pool_name)
    :poolboy.checkout(pool, block, timeout)
  end

  @doc """
  Returns an agent to the pool after use.

  ## Examples

      Jido.Agent.WorkerPool.checkin(MyApp.Jido, :fast_search, pid)
  """
  @spec checkin(instance(), pool_name(), pid()) :: :ok
  def checkin(jido_instance, pool_name, pid) do
    pool = Jido.agent_pool_name(jido_instance, pool_name)
    :poolboy.checkin(pool, pid)
  end

  @doc """
  Returns the current status of a pool.

  ## Examples

      status = Jido.Agent.WorkerPool.status(MyApp.Jido, :fast_search)
      # => %{size: 8, overflow: 0, available: 5, waiting: 0}
  """
  @spec status(instance(), pool_name()) :: map()
  def status(jido_instance, pool_name) do
    pool = Jido.agent_pool_name(jido_instance, pool_name)

    case :poolboy.status(pool) do
      {state_name, available_workers, overflow, checked_out} ->
        %{
          state: state_name,
          available: available_workers,
          overflow: overflow,
          checked_out: checked_out
        }
    end
  end

  @doc false
  @spec build_pool_child_specs(instance(), [{pool_name(), module(), keyword()}]) :: [tuple()]
  def build_pool_child_specs(jido_instance, pool_configs) do
    Enum.map(pool_configs, fn {pool_name, agent_module, pool_opts} ->
      build_pool_child_spec(jido_instance, pool_name, agent_module, pool_opts)
    end)
  end

  @doc false
  @spec build_pool_child_spec(instance(), pool_name(), module(), keyword()) :: tuple()
  def build_pool_child_spec(jido_instance, pool_name, agent_module, pool_opts) do
    pool_id = Jido.agent_pool_name(jido_instance, pool_name)

    poolboy_opts = [
      name: {:local, pool_id},
      worker_module: Jido.AgentServer,
      size: Keyword.get(pool_opts, :size, 5),
      max_overflow: Keyword.get(pool_opts, :max_overflow, 0),
      strategy: Keyword.get(pool_opts, :strategy, :lifo)
    ]

    worker_args =
      [agent: agent_module, jido: jido_instance] ++
        Keyword.get(pool_opts, :worker_opts, [])

    :poolboy.child_spec(pool_id, poolboy_opts, worker_args)
  end
end
