defmodule Jido.Agent.WorkerTest do
  use ExUnit.Case, async: true
  require Logger

  alias Jido.Signal
  alias Jido.Agent.Worker
  alias JidoTest.SimpleAgent

  setup do
    Logger.configure(level: :debug)
    {:ok, _} = start_supervised({Phoenix.PubSub, name: TestPubSub})
    {:ok, _} = start_supervised({Registry, keys: :unique, name: Jido.AgentRegistry})
    agent = SimpleAgent.new("test_agent")
    %{agent: agent}
  end

  # Helper functions for topic-specific assertions
  defp assert_signal(type, timeout \\ 2000) do
    assert_receive %Signal{type: ^type} = signal, timeout
    signal
  end

  describe "initialization" do
    test "starts worker with valid agent and pubsub", %{agent: agent} do
      topic = "jido.agent.#{agent.id}"
      :ok = Phoenix.PubSub.subscribe(TestPubSub, topic)
      # Add a small delay to ensure subscription is ready
      Process.sleep(10)

      {:ok, pid} = Worker.start_link(agent: agent, pubsub: TestPubSub)
      assert Process.alive?(pid)

      assert_signal("jido.agent.started")

      state = :sys.get_state(pid)
      assert state.agent.id == agent.id
      assert state.status == :idle
    end

    test "fails to start with missing pubsub", %{agent: agent} do
      assert_raise KeyError, ~r/key :pubsub not found/, fn ->
        Worker.start_link(agent: agent)
      end
    end
  end

  describe "command handling" do
    setup %{agent: agent} do
      topic = "jido.agent.#{agent.id}"
      :ok = Phoenix.PubSub.subscribe(TestPubSub, topic)
      # Add a small delay to ensure subscription is ready
      Process.sleep(10)

      {:ok, pid} = Worker.start_link(agent: agent, pubsub: TestPubSub)
      assert_signal("jido.agent.started")
      %{worker: pid}
    end

    test "act/2 processes agent actions", %{worker: pid} do
      :ok = Worker.act(pid, %{command: :move, location: :kitchen})
      signal = assert_signal("jido.agent.act_completed")
      assert signal.data.final_state.location == :kitchen
    end

    test "manage/3 handles pause command", %{worker: pid} do
      {:ok, state} = Worker.manage(pid, :pause)
      assert state.status == :paused
    end

    test "manage/3 handles resume from paused state", %{worker: pid} do
      {:ok, paused_state} = Worker.manage(pid, :pause)
      assert paused_state.status == :paused

      {:ok, resumed_state} = Worker.manage(pid, :resume)
      assert resumed_state.status == :running
    end

    test "manage/3 handles reset command", %{worker: pid} do
      :ok = Worker.act(pid, %{command: :move, location: :kitchen})
      assert_signal("jido.agent.act_completed")

      {:ok, reset_state} = Worker.manage(pid, :reset)
      assert reset_state.status == :idle
      assert :queue.len(reset_state.agent.pending) == 0
    end
  end

  # describe "command queueing" do
  #   setup %{agent: agent} do
  #     {:ok, pid} = Worker.start_link(agent: agent, pubsub: TestPubSub)
  #     :ok = Phoenix.PubSub.subscribe(TestPubSub, "jido.agent.#{agent.id}")
  #     assert_signal("jido.agent.started")
  #     %{worker: pid}
  #   end

  #   test "queues commands when paused", %{worker: pid} do
  #     {:ok, paused_state} = Worker.manage(pid, :pause)
  #     assert paused_state.status == :paused

  #     :ok = Worker.act(pid, %{input: "test1"})
  #     :ok = Worker.act(pid, %{input: "test2"})

  #     state = :sys.get_state(pid)
  #     assert :queue.len(state.pending) == 2

  #     {:ok, _} = Worker.manage(pid, :resume)

  #     signal = assert_signal("jido.agent.act_completed")
  #     assert signal.data.final_state.input == "test1"

  #     signal = assert_signal("jido.agent.act_completed")
  #     assert signal.data.final_state.input == "test2"
  #   end
  # end

  # describe "pubsub handling" do
  #   setup %{agent: agent} do
  #     {:ok, pid} = Worker.start_link(agent: agent, pubsub: TestPubSub)
  #     topic = "jido.agent.#{agent.id}"
  #     :ok = Phoenix.PubSub.subscribe(TestPubSub, topic)
  #     assert_signal("jido.agent.started")
  #     %{worker: pid, topic: topic}
  #   end

  #   test "handles act signals via pubsub", %{worker: pid, topic: topic} do
  #     {:ok, signal} =
  #       Signal.new(%{
  #         type: "jido.agent.act",
  #         source: "/test",
  #         data: %{input: "via_pubsub"}
  #       })

  #     Phoenix.PubSub.broadcast(TestPubSub, topic, signal)

  #     signal = assert_signal("jido.agent.act_completed")
  #     assert signal.data.final_state.input == "via_pubsub"
  #   end

  #   test "handles manage signals via pubsub", %{worker: pid, topic: topic} do
  #     {:ok, signal} =
  #       Signal.new(%{
  #         type: "jido.agent.manage",
  #         source: "/test",
  #         data: %{command: :pause}
  #       })

  #     Phoenix.PubSub.broadcast(TestPubSub, topic, signal)
  #     state = :sys.get_state(pid)
  #     assert state.status == :paused
  #   end
  # end
end
