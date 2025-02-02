defmodule Jido.Agent.Server.ProcessTest do
  use ExUnit.Case, async: true
  require Logger
  import ExUnit.CaptureLog

  alias Jido.Agent.Server.Process, as: ServerProcess
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Agent.Server.Signal, as: ServerSignal
  alias JidoTest.TestAgents.BasicAgent

  setup do
    {:ok, supervisor} = start_supervised(DynamicSupervisor)
    agent = BasicAgent.new("test")

    state = %ServerState{
      agent: agent,
      child_supervisor: supervisor,
      output: [
        out: {:pid, [target: self(), delivery_mode: :async]},
        log: {:pid, [target: self(), delivery_mode: :async]},
        err: {:pid, [target: self(), delivery_mode: :async]}
      ],
      status: :idle,
      pending_signals: :queue.new()
    }

    {:ok, state: state}
  end

  describe "start/2" do
    test "starts a child process and emits signal", %{state: state} do
      child_spec = %{
        id: :test_child,
        start: {Task, :start_link, [fn -> Process.sleep(:infinity) end]}
      }

      assert {:ok, %ServerState{}, pid} = ServerProcess.start(state, child_spec)
      assert Process.alive?(pid)

      assert_receive {:signal, signal}
      assert signal.type =~ ServerSignal.process_started()
      assert signal.data.child_pid == pid
      assert signal.data.child_spec == child_spec
    end

    test "emits failure signal when start fails", %{state: state} do
      invalid_spec = %{
        id: :invalid_child,
        start: {:not_a_module, :not_a_function, []}
      }

      capture_log(fn ->
        assert {:error, _reason} = ServerProcess.start(state, invalid_spec)
      end)

      assert_receive {:signal, signal}
      assert signal.type =~ ServerSignal.process_failed()
      assert signal.data.child_spec == invalid_spec
      assert signal.data.error != nil
    end
  end

  describe "list/1" do
    test "lists running child processes", %{state: state} do
      # Start a few test processes
      child_spec1 = %{
        id: :test_child1,
        start: {Task, :start_link, [fn -> Process.sleep(:infinity) end]}
      }

      child_spec2 = %{
        id: :test_child2,
        start: {Task, :start_link, [fn -> Process.sleep(:infinity) end]}
      }

      {:ok, new_state, pid1} = ServerProcess.start(state, child_spec1)
      {:ok, new_state, pid2} = ServerProcess.start(new_state, child_spec2)

      children = ServerProcess.list(new_state)
      assert length(children) == 2

      pids = Enum.map(children, fn {:undefined, pid, :worker, _} -> pid end)
      assert pid1 in pids
      assert pid2 in pids
    end

    test "returns empty list when no children", %{state: state} do
      assert [] = ServerProcess.list(state)
    end
  end

  describe "terminate/2" do
    test "terminates a specific child process and emits signal", %{state: state} do
      child_spec = %{
        id: :test_child,
        start: {Task, :start_link, [fn -> Process.sleep(:infinity) end]}
      }

      {:ok, new_state, pid} = ServerProcess.start(state, child_spec)
      assert Process.alive?(pid)

      # Clear the start signal
      assert_receive {:signal, _}

      assert :ok = ServerProcess.terminate(new_state, pid)
      refute Process.alive?(pid)

      assert_receive {:signal, signal}
      assert signal.type =~ ServerSignal.process_terminated()
      assert signal.data.child_pid == pid
    end

    test "returns error when terminating non-existent process", %{state: state} do
      non_existent_pid = spawn(fn -> :ok end)
      Process.exit(non_existent_pid, :kill)

      assert {:error, :not_found} = ServerProcess.terminate(state, non_existent_pid)
    end
  end

  describe "restart/3" do
    test "restarts a child process and emits signals", %{state: state} do
      child_spec = %{
        id: :test_child,
        start: {Task, :start_link, [fn -> Process.sleep(:infinity) end]}
      }

      {:ok, new_state, old_pid} = ServerProcess.start(state, child_spec)
      assert Process.alive?(old_pid)

      # Clear the start signal
      assert_receive {:signal, _}

      {:ok, %ServerState{}, new_pid} = ServerProcess.restart(new_state, old_pid, child_spec)
      assert Process.alive?(new_pid)
      refute Process.alive?(old_pid)
      assert old_pid != new_pid

      # Should receive terminated and started signals
      assert_receive {:signal, signal1}
      assert signal1.type =~ ServerSignal.process_terminated()
      assert signal1.data.child_pid == old_pid

      assert_receive {:signal, signal2}
      assert signal2.type =~ ServerSignal.process_started()
      assert signal2.data.child_pid == new_pid
      assert signal2.data.child_spec == child_spec
    end

    test "emits failure signal when restart fails", %{state: state} do
      child_spec = %{
        id: :test_child,
        start: {Task, :start_link, [fn -> Process.sleep(:infinity) end]}
      }

      {:ok, new_state, old_pid} = ServerProcess.start(state, child_spec)
      # Clear the start signal
      assert_receive {:signal, _}

      invalid_spec = %{
        id: :invalid_child,
        start: {:not_a_module, :not_a_function, []}
      }

      capture_log(fn ->
        assert {:error, _reason} = ServerProcess.restart(new_state, old_pid, invalid_spec)
      end)

      # Should receive terminated and failed signals
      assert_receive {:signal, signal1}
      assert signal1.type =~ ServerSignal.process_terminated()
      assert signal1.data.child_pid == old_pid

      assert_receive {:signal, signal2}
      assert signal2.type =~ ServerSignal.process_failed()
      assert signal2.data.child_spec == invalid_spec
      assert signal2.data.error != nil
    end

    test "fails to restart non-existent process", %{state: state} do
      non_existent_pid = spawn(fn -> :ok end)
      Process.exit(non_existent_pid, :kill)

      child_spec = %{
        id: :test_child,
        start: {Task, :start_link, [fn -> Process.sleep(:infinity) end]}
      }

      assert {:error, :not_found} = ServerProcess.restart(state, non_existent_pid, child_spec)

      assert_receive {:signal, signal}
      assert signal.type =~ ServerSignal.process_failed()
      assert signal.data.child_pid == non_existent_pid
      assert signal.data.child_spec == child_spec
      assert signal.data.error == {:error, :not_found}
    end
  end
end
