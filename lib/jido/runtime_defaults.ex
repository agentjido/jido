defmodule Jido.RuntimeDefaults do
  @moduledoc """
  Centralized runtime defaults for timeouts, limits, and supervisor guardrails.

  Values can be overridden via application config:

      config :jido, Jido.RuntimeDefaults,
        agent_server_call_timeout: 10_000,
        agent_server_shutdown_timeout: 5_000,
        await_timeout: 10_000,
        await_child_timeout: 30_000,
        plugin_hook_timeout: 1_000,
        stop_child_shutdown_timeout: 5_000,
        instance_manager_stop_timeout: 5_000,
        sensor_runtime_shutdown_timeout: 5_000,
        jido_supervisor_shutdown_timeout: 10_000,
        agent_supervisor_max_restarts: 1_000,
        agent_supervisor_max_seconds: 5,
        instance_manager_max_restarts: 100,
        instance_manager_max_seconds: 5,
        status_call_timeout: 1_000,
        stream_status_interval_ms: 250,
        debug_event_buffer_size: 50,
        max_agents: 10_000,
        max_tasks: 1_000,
        system_task_max_children: 2_000,
        worker_pool_timeout: 5_000,
        worker_pool_call_timeout: 5_000
  """

  @app :jido
  @config_key __MODULE__

  @agent_server_call_timeout 10_000
  @agent_server_shutdown_timeout 5_000
  @await_timeout 10_000
  @await_child_timeout 30_000
  @plugin_hook_timeout 1_000
  @stop_child_shutdown_timeout 5_000
  @instance_manager_stop_timeout 5_000
  @sensor_runtime_shutdown_timeout 5_000
  @jido_supervisor_shutdown_timeout 10_000
  @agent_supervisor_max_restarts 1_000
  @agent_supervisor_max_seconds 5
  @instance_manager_max_restarts 100
  @instance_manager_max_seconds 5
  @status_call_timeout 1_000
  @stream_status_interval_ms 250
  @debug_event_buffer_size 50
  @hibernate_timeout 2_000
  @max_queue_size 10_000
  @max_agents 10_000
  @max_tasks 1_000
  @system_task_max_children 2_000
  @worker_pool_timeout 5_000
  @worker_pool_call_timeout 5_000

  @spec agent_server_call_timeout() :: pos_integer()
  def agent_server_call_timeout,
    do: get(:agent_server_call_timeout, @agent_server_call_timeout)

  @spec agent_server_shutdown_timeout() :: pos_integer()
  def agent_server_shutdown_timeout,
    do: get(:agent_server_shutdown_timeout, @agent_server_shutdown_timeout)

  @spec await_timeout() :: pos_integer()
  def await_timeout, do: get(:await_timeout, @await_timeout)

  @spec await_child_timeout() :: pos_integer()
  def await_child_timeout, do: get(:await_child_timeout, @await_child_timeout)

  @spec plugin_hook_timeout() :: pos_integer()
  def plugin_hook_timeout, do: get(:plugin_hook_timeout, @plugin_hook_timeout)

  @spec stop_child_shutdown_timeout() :: pos_integer()
  def stop_child_shutdown_timeout,
    do: get(:stop_child_shutdown_timeout, @stop_child_shutdown_timeout)

  @spec instance_manager_stop_timeout() :: pos_integer()
  def instance_manager_stop_timeout,
    do: get(:instance_manager_stop_timeout, @instance_manager_stop_timeout)

  @spec sensor_runtime_shutdown_timeout() :: pos_integer()
  def sensor_runtime_shutdown_timeout,
    do: get(:sensor_runtime_shutdown_timeout, @sensor_runtime_shutdown_timeout)

  @spec jido_supervisor_shutdown_timeout() :: pos_integer()
  def jido_supervisor_shutdown_timeout,
    do: get(:jido_supervisor_shutdown_timeout, @jido_supervisor_shutdown_timeout)

  @spec agent_supervisor_max_restarts() :: pos_integer()
  def agent_supervisor_max_restarts,
    do: get(:agent_supervisor_max_restarts, @agent_supervisor_max_restarts)

  @spec agent_supervisor_max_seconds() :: pos_integer()
  def agent_supervisor_max_seconds,
    do: get(:agent_supervisor_max_seconds, @agent_supervisor_max_seconds)

  @spec instance_manager_max_restarts() :: pos_integer()
  def instance_manager_max_restarts,
    do: get(:instance_manager_max_restarts, @instance_manager_max_restarts)

  @spec instance_manager_max_seconds() :: pos_integer()
  def instance_manager_max_seconds,
    do: get(:instance_manager_max_seconds, @instance_manager_max_seconds)

  @spec status_call_timeout() :: pos_integer()
  def status_call_timeout,
    do: get(:status_call_timeout, @status_call_timeout)

  @spec stream_status_interval_ms() :: pos_integer()
  def stream_status_interval_ms,
    do: get(:stream_status_interval_ms, @stream_status_interval_ms)

  @spec debug_event_buffer_size() :: pos_integer()
  def debug_event_buffer_size,
    do: get(:debug_event_buffer_size, @debug_event_buffer_size)

  @spec hibernate_timeout() :: pos_integer()
  def hibernate_timeout, do: get(:hibernate_timeout, @hibernate_timeout)

  @spec max_agents() :: pos_integer()
  def max_agents, do: get(:max_agents, @max_agents)

  @spec max_queue_size() :: pos_integer()
  def max_queue_size, do: get(:max_queue_size, @max_queue_size)

  @spec max_tasks() :: pos_integer()
  def max_tasks, do: get(:max_tasks, @max_tasks)

  @spec system_task_max_children() :: pos_integer()
  def system_task_max_children,
    do: get(:system_task_max_children, @system_task_max_children)

  @spec worker_pool_timeout() :: pos_integer()
  def worker_pool_timeout, do: get(:worker_pool_timeout, @worker_pool_timeout)

  @spec worker_pool_call_timeout() :: pos_integer()
  def worker_pool_call_timeout,
    do: get(:worker_pool_call_timeout, @worker_pool_call_timeout)

  defp get(key, default) do
    @app
    |> Application.get_env(@config_key, [])
    |> Keyword.get(key, default)
  end
end
