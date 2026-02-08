defmodule JidoTest.RuntimeDefaultsTest do
  use ExUnit.Case, async: false

  alias Jido.RuntimeDefaults

  setup do
    previous = Application.get_env(:jido, RuntimeDefaults)

    on_exit(fn ->
      if previous == nil do
        Application.delete_env(:jido, RuntimeDefaults)
      else
        Application.put_env(:jido, RuntimeDefaults, previous)
      end
    end)

    :ok
  end

  test "exposes centralized defaults for shutdown and supervisor guardrails" do
    Application.delete_env(:jido, RuntimeDefaults)

    assert RuntimeDefaults.agent_server_shutdown_timeout() == 5_000
    assert RuntimeDefaults.sensor_runtime_shutdown_timeout() == 5_000
    assert RuntimeDefaults.instance_manager_stop_timeout() == 5_000
    assert RuntimeDefaults.stop_child_shutdown_timeout() == 5_000
    assert RuntimeDefaults.await_child_timeout() == 30_000
    assert RuntimeDefaults.jido_supervisor_shutdown_timeout() == 10_000
    assert RuntimeDefaults.agent_supervisor_max_restarts() == 1_000
    assert RuntimeDefaults.agent_supervisor_max_seconds() == 5
    assert RuntimeDefaults.instance_manager_max_restarts() == 100
    assert RuntimeDefaults.instance_manager_max_seconds() == 5
    assert RuntimeDefaults.debug_event_buffer_size() == 50
  end

  test "reads runtime overrides for shutdown and supervisor guardrails" do
    Application.put_env(:jido, RuntimeDefaults,
      agent_server_shutdown_timeout: 1_111,
      sensor_runtime_shutdown_timeout: 2_222,
      instance_manager_stop_timeout: 3_333,
      stop_child_shutdown_timeout: 4_444,
      await_child_timeout: 55_555,
      jido_supervisor_shutdown_timeout: 6_666,
      agent_supervisor_max_restarts: 77,
      agent_supervisor_max_seconds: 88,
      instance_manager_max_restarts: 99,
      instance_manager_max_seconds: 44,
      debug_event_buffer_size: 123
    )

    assert RuntimeDefaults.agent_server_shutdown_timeout() == 1_111
    assert RuntimeDefaults.sensor_runtime_shutdown_timeout() == 2_222
    assert RuntimeDefaults.instance_manager_stop_timeout() == 3_333
    assert RuntimeDefaults.stop_child_shutdown_timeout() == 4_444
    assert RuntimeDefaults.await_child_timeout() == 55_555
    assert RuntimeDefaults.jido_supervisor_shutdown_timeout() == 6_666
    assert RuntimeDefaults.agent_supervisor_max_restarts() == 77
    assert RuntimeDefaults.agent_supervisor_max_seconds() == 88
    assert RuntimeDefaults.instance_manager_max_restarts() == 99
    assert RuntimeDefaults.instance_manager_max_seconds() == 44
    assert RuntimeDefaults.debug_event_buffer_size() == 123
  end
end
