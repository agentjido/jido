defmodule Jido.Agent.WorkerTest do
  use ExUnit.Case, async: true
  import Mimic
  require Logger

  alias Jido.Signal
  alias Jido.Agent.Worker
  alias JidoTest.SimpleAgent

  setup :set_mimic_global

  setup do
    Logger.configure(level: :debug)
    {:ok, _} = start_supervised({Phoenix.PubSub, name: TestPubSub})
    {:ok, _} = start_supervised({Registry, keys: :unique, name: Jido.AgentRegistry})
    agent = SimpleAgent.new("test_agent")
    %{agent: agent}
  end

  # Helper functions for topic-specific assertions
  defp subscribe_to_topics(%{input: input, emit: emit, metrics: metrics}) do
    :ok = Phoenix.PubSub.subscribe(TestPubSub, input)
    :ok = Phoenix.PubSub.subscribe(TestPubSub, emit)
    :ok = Phoenix.PubSub.subscribe(TestPubSub, metrics)
  end

  defp assert_emitted_signal(type, timeout \\ 2000) do
    assert_receive %Signal{type: ^type} = signal, timeout
    signal
  end

  defp assert_metric_signal(type, timeout \\ 2000) do
    assert_receive %Signal{type: ^type} = signal, timeout
    signal
  end

  describe "initialization" do
    test "start_link/1 starts the worker and emits metric", %{agent: agent} do
      # Only subscribe to metrics topic for initialization
      :ok = Phoenix.PubSub.subscribe(TestPubSub, "jido.agent.#{agent.id}/metrics")

      {:ok, pid} = Worker.start_link(agent: agent, pubsub: TestPubSub)
      assert Process.alive?(pid)

      # Verify startup metric
      assert_metric_signal("jido.agent.started")

      state = :sys.get_state(pid)
      assert state.agent.id == agent.id
      assert state.status == :idle
    end
  end

  # describe "state management" do
  #   setup %{agent: agent} do
  #     name = "#{agent.id}_#{:erlang.unique_integer([:positive])}"
  #     agent = %{agent | id: name}
  #     base = "jido.agent.#{agent.id}"

  #     topics = %{
  #       input: base,
  #       emit: "#{base}/emit",
  #       metrics: "#{base}/metrics"
  #     }

  #     # Subscribe to all topics
  #     subscribe_to_topics(topics)

  #     {:ok, pid} = Worker.start_link(agent: agent, pubsub: TestPubSub, name: name)

  #     # Clear the startup metric
  #     assert_metric_signal("jido.agent.started")

  #     %{worker: pid, agent: agent, topics: topics}
  #   end

  #   test "set/2 updates agent state and emits signal", %{worker: pid} do
  #     :ok = Worker.set(pid, %{location: :office})

  #     # Action events go to emit topic
  #     signal = assert_emitted_signal("jido.agent.set_processed")
  #     assert signal.data.attrs.location == :office

  #     state = :sys.get_state(pid)
  #     assert state.agent.location == :office
  #   end

  #   test "set/2 with invalid data emits error signal", %{worker: pid} do
  #     :ok = Worker.set(pid, %{battery_level: "not a number"})

  #     # Error events go to emit topic
  #     signal = assert_emitted_signal("jido.agent.set_failed")
  #     assert signal.data.error != nil

  #     state = :sys.get_state(pid)
  #     refute state.agent.battery_level == "not a number"
  #   end

  #   test "set/2 ignores nil input and emits error", %{worker: pid} do
  #     :ok = Worker.set(pid, nil)

  #     signal = assert_emitted_signal("jido.agent.set_failed")
  #     assert signal.data.error == "nil attrs not allowed"
  #   end

  #   test "act/2 updates agent state and emits completion", %{worker: pid} do
  #     :ok = Worker.act(pid, %{battery_level: 50})

  #     signal = assert_emitted_signal("jido.agent.act_completed")
  #     assert signal.data.final_state.battery_level == 50

  #     state = :sys.get_state(pid)
  #     assert state.agent.battery_level == 50
  #     assert state.status == :idle
  #   end

  #   test "act/2 with invalid attrs emits failure", %{worker: pid} do
  #     :ok = Worker.act(pid, %{battery_level: "invalid"})

  #     signal = assert_emitted_signal("jido.agent.act_failed")
  #     assert signal.data.error != nil

  #     state = :sys.get_state(pid)
  #     # Default value
  #     assert state.agent.battery_level == 100
  #   end
  # end

  # describe "command handling" do
  #   setup %{agent: agent} do
  #     name = "#{agent.id}_#{:erlang.unique_integer([:positive])}"
  #     agent = %{agent | id: name}

  #     topics = %{
  #       input: "jido.agent.#{name}",
  #       emit: "jido.agent.#{name}/emit",
  #       metrics: "jido.agent.#{name}/metrics"
  #     }

  #     subscribe_to_topics(topics)

  #     {:ok, pid} = Worker.start_link(agent: agent, pubsub: TestPubSub, name: name)

  #     # Clear the startup metric
  #     assert_metric_signal("jido.agent.started")

  #     %{worker: pid, agent: agent, topics: topics}
  #   end

  #   test "pause command pauses the worker and emits event", %{worker: pid} do
  #     assert {:ok, state} = Worker.cmd(pid, :pause)

  #     signal = assert_emitted_signal("jido.agent.pause_completed")
  #     assert signal.data.args == nil
  #     assert state.status == :paused
  #   end

  #   test "resume command resumes the worker and emits event", %{worker: pid} do
  #     {:ok, paused_state} = Worker.cmd(pid, :pause)
  #     assert paused_state.status == :paused
  #     assert_emitted_signal("jido.agent.pause_completed")

  #     {:ok, resumed_state} = Worker.cmd(pid, :resume)
  #     assert resumed_state.status == :running
  #     assert_emitted_signal("jido.agent.resume_completed")
  #   end
  # end

  # describe "pubsub message handling" do
  #   setup %{agent: agent} do
  #     name = "#{agent.id}_#{:erlang.unique_integer([:positive])}"
  #     agent = %{agent | id: name}

  #     topics = %{
  #       input: "jido.agent.#{name}",
  #       emit: "jido.agent.#{name}/emit",
  #       metrics: "jido.agent.#{name}/metrics"
  #     }

  #     subscribe_to_topics(topics)

  #     {:ok, pid} = Worker.start_link(agent: agent, pubsub: TestPubSub, name: name)

  #     # Clear the startup metric
  #     assert_metric_signal("jido.agent.started")

  #     %{worker: pid, agent: agent, topics: topics}
  #   end

  #   test "handles set command via pubsub", %{worker: pid, topics: topics} do
  #     signal = %Signal{
  #       type: "jido.agent.set",
  #       source: "/test",
  #       data: %{location: :kitchen}
  #     }

  #     Phoenix.PubSub.broadcast(TestPubSub, topics.input, signal)

  #     response = assert_emitted_signal("jido.agent.set_processed")
  #     assert response.data.attrs.location == :kitchen

  #     state = :sys.get_state(pid)
  #     assert state.agent.location == :kitchen
  #   end

  #   test "handles act command via pubsub", %{worker: pid, topics: topics} do
  #     signal = %Signal{
  #       type: "jido.agent.act",
  #       source: "/test",
  #       data: %{battery_level: 75}
  #     }

  #     Phoenix.PubSub.broadcast(TestPubSub, topics.input, signal)

  #     response = assert_emitted_signal("jido.agent.act_completed")
  #     assert response.data.final_state.battery_level == 75

  #     state = :sys.get_state(pid)
  #     assert state.agent.battery_level == 75
  #   end
  # end
end
