defmodule Jido.Agent.Server.CallbackTest do
  use JidoTest.Case, async: true
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Agent.Server.Callback
  alias Jido.Signal
  alias JidoTest.TestAgents.CallbackTrackingAgent
  alias JidoTest.TestSkills.TestSkill

  setup do
    agent = %CallbackTrackingAgent{
      id: Jido.Util.generate_id(),
      state: %{
        callback_log: [],
        callback_count: %{}
      },
      dirty_state?: false,
      pending_instructions: :queue.new(),
      actions: [],
      result: nil
    }

    state = %ServerState{
      agent: agent,
      skills: [TestSkill]
    }

    {:ok, %{state: state}}
  end

  describe "agent callbacks" do
    test "mount callback", %{state: state} do
      {:ok, updated_state} = Callback.mount(state)
      assert get_in(updated_state.agent.state, [:callback_count, :mount]) == 1
    end

    test "code_change callback", %{state: state} do
      old_vsn = "1.0.0"
      extra = %{data: "test"}
      {:ok, updated_state} = Callback.code_change(state, old_vsn, extra)
      assert get_in(updated_state.agent.state, [:callback_count, :code_change]) == 1
    end

    test "shutdown callback", %{state: state} do
      reason = :normal
      {:ok, updated_state} = Callback.shutdown(state, reason)
      assert get_in(updated_state.agent.state, [:callback_count, :shutdown]) == 1
    end
  end

  describe "signal handling" do
    test "handle_signal with agent", %{state: state} do
      signal = Signal.new(%{type: "test.agent", data: %{}})
      {:ok, handled_signal} = Callback.handle_signal(state, signal)
      assert get_in(handled_signal.data, [:agent_handled]) == true
    end

    test "handle_signal with skill", %{state: state} do
      signal = Signal.new(%{type: "test.skill.action", data: %{}})
      {:ok, handled_signal} = Callback.handle_signal(state, signal)
      assert get_in(handled_signal.data, [:skill_handled]) == true
    end

    test "handle_signal with both agent and skill", %{state: state} do
      signal = Signal.new(%{type: "test.skill.action", data: %{}})
      {:ok, handled_signal} = Callback.handle_signal(state, signal)
      assert get_in(handled_signal.data, [:agent_handled]) == true
      assert get_in(handled_signal.data, [:skill_handled]) == true
    end

    test "transform_result with agent", %{state: state} do
      signal = Signal.new(%{type: "test.agent", data: %{}})
      {:ok, processed} = Callback.transform_result(state, signal, %{})
      assert get_in(processed, [:agent_processed]) == true
    end

    test "transform_result with skill", %{state: state} do
      signal = Signal.new(%{type: "test.skill.action", data: %{}})
      {:ok, processed} = Callback.transform_result(state, signal, %{})
      assert get_in(processed, [:skill_processed]) == true
    end

    test "transform_result with both agent and skill", %{state: state} do
      signal = Signal.new(%{type: "test.skill.action", data: %{}})
      {:ok, processed} = Callback.transform_result(state, signal, %{})
      assert get_in(processed, [:agent_processed]) == true
      assert get_in(processed, [:skill_processed]) == true
    end
  end
end
