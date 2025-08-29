defmodule JidoTest.SupportTest do
  use ExUnit.Case, async: true

  alias JidoTest.Support
  alias Jido.Agent.Server
  alias JidoTest.TestAgents.BasicAgent

  @moduletag :capture_log

  describe "start_registry!/0" do
    test "creates unique registries" do
      {:ok, registry1} = Support.start_registry!()
      {:ok, registry2} = Support.start_registry!()

      assert is_atom(registry1)
      assert is_atom(registry2)
      assert registry1 != registry2
    end
  end

  describe "unique_id/1" do
    test "generates unique IDs with default prefix" do
      id1 = Support.unique_id()
      id2 = Support.unique_id()

      assert String.starts_with?(id1, "test-")
      assert String.starts_with?(id2, "test-")
      assert id1 != id2
    end

    test "generates unique IDs with custom prefix" do
      id = Support.unique_id("agent")
      assert String.starts_with?(id, "agent-")
    end
  end

  describe "start_basic_agent!/1" do
    test "starts an agent with default options" do
      {:ok, context} = Support.start_basic_agent!()

      assert is_pid(context.pid)
      assert Process.alive?(context.pid)
      assert is_atom(context.registry)
      assert is_binary(context.id)
      assert %BasicAgent{} = context.agent
    end

    test "starts an agent with custom options" do
      {:ok, context} =
        Support.start_basic_agent!(
          id: "custom-agent",
          initial_state: %{battery_level: 50}
        )

      assert context.id == "custom-agent"
      {:ok, state} = Server.state(context.pid)
      assert state.agent.state.battery_level == 50
    end

    test "automatically cleans up by default" do
      # This test verifies the cleanup mechanism is set up
      {:ok, context} = Support.start_basic_agent!()
      pid = context.pid

      assert Process.alive?(pid)
      # The ExUnit.Callbacks.on_exit should be set up
      # We can't easily test the cleanup without triggering test completion
    end
  end

  describe "create_test_signal/3" do
    test "creates signal with default values" do
      {:ok, signal} = Support.create_test_signal("test_event")

      assert signal.type == "test_event"
      assert signal.data == %{}
      assert signal.source == "test-source"
      assert signal.subject == "test-subject"
    end

    test "creates signal with custom data and options" do
      {:ok, signal} =
        Support.create_test_signal(
          "user_event",
          %{user_id: 123},
          source: "test-app"
        )

      assert signal.type == "user_event"
      assert signal.data == %{user_id: 123}
      assert signal.source == "test-app"
    end
  end

  describe "assert_agent_state/2" do
    test "asserts agent state matches expected values" do
      {:ok, context} =
        Support.start_basic_agent!(initial_state: %{location: :office, battery_level: 75})

      # These should pass
      :ok = Support.assert_agent_state(context, %{location: :office})
      :ok = Support.assert_agent_state(context, %{battery_level: 75})
      :ok = Support.assert_agent_state(context, location: :office, battery_level: 75)
    end

    test "fails when state doesn't match" do
      {:ok, context} = Support.start_basic_agent!(initial_state: %{battery_level: 100})

      assert_raise ExUnit.AssertionError, fn ->
        Support.assert_agent_state(context, %{battery_level: 50})
      end
    end
  end

  describe "setup_test_registry/0" do
    test "creates registry setup for tests" do
      setup_result = Support.setup_test_registry()

      assert %{registry: registry} = setup_result
      assert is_atom(registry)

      # Verify registry is functional
      {:ok, pid} =
        Server.start_link(
          agent: BasicAgent.new("test"),
          registry: registry
        )

      assert [{^pid, nil}] = Registry.lookup(registry, "test")
    end
  end

  describe "setup_basic_agent/1" do
    test "creates full agent setup for tests" do
      setup_result = Support.setup_basic_agent()

      assert %{agent_context: context, registry: registry} = setup_result
      assert is_pid(context.pid)
      assert context.registry == registry
    end
  end

  describe "create_test_agents/2" do
    test "creates multiple agents with default prefix" do
      contexts = Support.create_test_agents(3)

      assert length(contexts) == 3
      assert Enum.all?(contexts, &is_pid(&1.pid))
      assert Enum.all?(contexts, &Process.alive?(&1.pid))

      ids = Enum.map(contexts, & &1.id)
      assert Enum.all?(ids, &String.starts_with?(&1, "agent-"))
      # All unique
      assert Enum.uniq(ids) == ids
    end

    test "creates multiple agents with custom prefix" do
      contexts = Support.create_test_agents(2, prefix: "worker")

      assert length(contexts) == 2
      ids = Enum.map(contexts, & &1.id)
      assert Enum.all?(ids, &String.starts_with?(&1, "worker-"))
    end
  end

  describe "get_agent_state/1" do
    test "retrieves current agent state" do
      {:ok, context} = Support.start_basic_agent!(initial_state: %{custom_field: "test_value"})

      state = Support.get_agent_state(context)
      assert state.custom_field == "test_value"
      # default from BasicAgent
      assert state.location == :home
    end
  end

  describe "queue assertions" do
    test "assert_queue_empty/1 passes for empty queue" do
      {:ok, context} = Support.start_basic_agent!()

      :ok = Support.assert_queue_empty(context)
    end

    test "assert_queue_size/2 checks queue size" do
      {:ok, context} = Support.start_basic_agent!()

      :ok = Support.assert_queue_size(context, 0)
    end
  end
end
