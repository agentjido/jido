defmodule JidoTest.Agent.Server.SignalTest do
  use ExUnit.Case, async: true
  alias Jido.Agent.Server.Signal, as: ServerSignal
  alias Jido.Signal

  describe "syscall_signal/3" do
    test "creates syscall signal with state" do
      state = %{agent: %{id: "agent-123"}}
      {:ok, signal} = ServerSignal.syscall_signal(state, ServerSignal.process_start())

      assert signal.type == ServerSignal.process_start()
      assert signal.source == "jido"
      assert signal.subject == "agent-123"
      assert signal.data == %{}
    end
  end

  describe "event_signal/3" do
    test "creates event signal with state" do
      state = %{agent: %{id: "agent-123"}}
      {:ok, signal} = ServerSignal.event_signal(state, ServerSignal.started())

      assert signal.type == ServerSignal.started()
      assert signal.source == "jido"
      assert signal.subject == "agent-123"
      assert signal.data == %{}
    end

    test "creates event signal with payload" do
      state = %{agent: %{id: "agent-123"}}
      payload = %{key: "value"}
      {:ok, signal} = ServerSignal.event_signal(state, ServerSignal.started(), payload)

      assert signal.data == payload
    end
  end

  describe "action_signal/4" do
    test "creates command signal with single action" do
      {:ok, signal} = ServerSignal.action_signal("agent-123", :test_action)

      assert signal.type == ServerSignal.cmd()
      assert signal.subject == "agent-123"
      assert signal.jidoinstructions == [{:test_action, %{}}]
      assert signal.jidoopts == %{apply_state: true}
    end

    test "creates command signal with action tuple" do
      action = {:test_action, %{arg: "value"}}
      {:ok, signal} = ServerSignal.action_signal("agent-123", action)

      assert signal.jidoinstructions == [{:test_action, %{arg: "value"}}]
    end

    test "creates command signal with action list" do
      actions = [
        {:action1, %{arg1: "val1"}},
        {:action2, %{arg2: "val2"}}
      ]

      {:ok, signal} = ServerSignal.action_signal("agent-123", actions)

      assert signal.jidoinstructions == actions
    end

    test "accepts custom args and opts" do
      args = %{custom: "value"}
      opts = [apply_state: false]
      {:ok, signal} = ServerSignal.action_signal("agent-123", :test, args, opts)

      assert signal.data == args
      assert signal.jidoopts == %{apply_state: false}
    end
  end

  describe "extract_actions/1" do
    test "extracts actions and options from valid signal" do
      signal = %Signal{
        id: "123",
        type: "jido.agent.cmd",
        source: "jido",
        subject: "agent-123",
        jidoinstructions: [{:test_action, %{param: "value"}}],
        jidoopts: %{apply_state: true},
        data: %{arg: "value"}
      }

      assert {:ok, {actions, data, opts}} = ServerSignal.extract_actions(signal)
      assert actions == [{:test_action, %{param: "value"}}]
      assert data == %{arg: "value"}
      assert opts == [apply_state: true]
    end

    test "returns error for invalid signal format" do
      invalid_signal = %Signal{
        id: "123",
        type: "jido.agent.cmd",
        source: "jido",
        subject: "agent-123",
        jidoinstructions: nil,
        jidoopts: nil
      }

      assert {:error, :invalid_signal_format} = ServerSignal.extract_actions(invalid_signal)
    end
  end

  describe "signal type predicates" do
    setup do
      {:ok, base_signal} =
        Signal.new(%{
          id: "123",
          source: "jido",
          type: "jido.agent.test",
          subject: "test-agent"
        })

      %{base_signal: base_signal}
    end

    test "is_agent_signal?" do
      {:ok, agent_signal} =
        Signal.new(%{
          id: "123",
          source: "jido",
          type: "jido.agent.test",
          subject: "test-agent"
        })

      {:ok, other_signal} =
        Signal.new(%{
          id: "123",
          source: "jido",
          type: "other",
          subject: "test-agent"
        })

      assert ServerSignal.is_agent_signal?(agent_signal)
      refute ServerSignal.is_agent_signal?(other_signal)
    end

    test "is_syscall_signal?" do
      {:ok, syscall_signal} =
        Signal.new(%{
          id: "123",
          source: "jido",
          type: "jido.agent.syscall.test",
          subject: "test-agent"
        })

      {:ok, other_signal} =
        Signal.new(%{
          id: "123",
          source: "jido",
          type: "other",
          subject: "test-agent"
        })

      assert ServerSignal.is_syscall_signal?(syscall_signal)
      refute ServerSignal.is_syscall_signal?(other_signal)
    end

    test "is_event_signal?" do
      {:ok, event_signal} =
        Signal.new(%{
          id: "123",
          source: "jido",
          type: "jido.agent.event.test",
          subject: "test-agent"
        })

      {:ok, other_signal} =
        Signal.new(%{
          id: "123",
          source: "jido",
          type: "other",
          subject: "test-agent"
        })

      assert ServerSignal.is_event_signal?(event_signal)
      refute ServerSignal.is_event_signal?(other_signal)
    end

    test "is_process_signal?" do
      {:ok, start_signal} =
        Signal.new(%{
          id: "123",
          source: "jido",
          type: ServerSignal.process_start(),
          subject: "test-agent"
        })

      {:ok, term_signal} =
        Signal.new(%{
          id: "123",
          source: "jido",
          type: ServerSignal.process_terminate(),
          subject: "test-agent"
        })

      {:ok, other_signal} =
        Signal.new(%{
          id: "123",
          source: "jido",
          type: "other",
          subject: "test-agent"
        })

      assert ServerSignal.is_process_signal?(start_signal)
      assert ServerSignal.is_process_signal?(term_signal)
      refute ServerSignal.is_process_signal?(other_signal)
    end
  end
end
