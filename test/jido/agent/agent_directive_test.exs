defmodule JidoTest.AgentDirectiveTest do
  use JidoTest.Case, async: true
  use Mimic

  alias JidoTest.TestAgents.BasicAgent

  alias JidoTest.TestActions.{
    BasicAction,
    NoSchema,
    EnqueueAction,
    RegisterAction,
    DeregisterAction
  }

  setup :verify_on_exit!
  @moduletag :capture_log

  describe "enqueue directives" do
    setup do
      agent = BasicAgent.new()
      {:ok, agent: agent}
    end

    test "successfully enqueues valid action via cmd", %{agent: agent} do
      {:ok, final, []} =
        BasicAgent.cmd(
          agent,
          {EnqueueAction,
           %{
             action: BasicAction,
             params: %{value: 42}
           }},
          %{},
          apply_state: true
        )

      # Verify action was enqueued
      assert {:value, instruction} = :queue.peek(final.pending_instructions)
      assert instruction.action == BasicAction
      assert instruction.params == %{value: 42}
    end

    test "maintains queue order with multiple enqueues", %{agent: agent} do
      # Plan first enqueue action without executing
      {:ok, agent_with_first} =
        BasicAgent.plan(agent, {EnqueueAction, %{action: BasicAction, params: %{value: 1}}})

      # Plan second enqueue action  
      {:ok, agent_with_both} =
        BasicAgent.plan(
          agent_with_first,
          {EnqueueAction, %{action: BasicAction, params: %{value: 2}}}
        )

      # Execute first EnqueueAction 
      {:ok, agent_after_first, []} = BasicAgent.run(agent_with_both)

      # Execute second EnqueueAction
      {:ok, final, []} = BasicAgent.run(agent_after_first)

      # Verify queue order - should have the originally enqueued actions plus the new ones
      {{:value, first}, queue} = :queue.out(final.pending_instructions)
      {{:value, second}, _} = :queue.out(queue)

      assert first.params.value == 1
      assert second.params.value == 2
    end
  end

  describe "register directives" do
    setup do
      # Start with a fresh agent that has only RegisterAction
      agent = BasicAgent.new()
      # Remove all actions except RegisterAction
      {:ok, agent} = BasicAgent.deregister_action(agent, BasicAction)
      {:ok, agent} = BasicAgent.deregister_action(agent, NoSchema)
      {:ok, agent} = BasicAgent.deregister_action(agent, EnqueueAction)
      {:ok, agent} = BasicAgent.deregister_action(agent, DeregisterAction)
      {:ok, agent: agent}
    end

    test "successfully registers new action module via plan and run", %{agent: agent} do
      {:ok, planned} =
        BasicAgent.plan(agent, {RegisterAction, %{action_module: BasicAction}})

      {:ok, final, []} = BasicAgent.run(planned)

      # Verify action was registered
      assert BasicAction in final.actions
      assert RegisterAction in final.actions
      assert length(final.actions) == 2
    end

    test "registers multiple action modules", %{agent: agent} do
      # First registration
      {:ok, agent_after_first, []} =
        BasicAgent.cmd(agent, {RegisterAction, %{action_module: BasicAction}}, %{})

      # Second registration
      {:ok, final, []} =
        BasicAgent.cmd(agent_after_first, {RegisterAction, %{action_module: NoSchema}}, %{})

      # Verify actions were registered
      assert BasicAction in final.actions
      assert NoSchema in final.actions
      assert RegisterAction in final.actions
      assert length(final.actions) == 3
    end

    test "idempotent registration of same module", %{agent: agent} do
      instructions = [
        {RegisterAction, %{action_module: BasicAction}},
        {RegisterAction, %{action_module: BasicAction}}
      ]

      {:ok, final, []} = BasicAgent.cmd(agent, instructions, %{})

      # Verify action was registered only once
      assert length(final.actions) == 2
      assert BasicAction in final.actions
      assert RegisterAction in final.actions
      refute NoSchema in final.actions
    end
  end

  describe "deregister directives" do
    setup do
      agent = BasicAgent.new()
      {:ok, agent: agent}
    end

    test "successfully deregisters existing action module", %{agent: agent} do
      {:ok, final, []} =
        BasicAgent.cmd(
          agent,
          {DeregisterAction, %{action_module: BasicAction}},
          %{}
        )

      # Verify action was deregistered
      refute BasicAction in final.actions
    end

    test "safely handles deregistering non-existent module", %{agent: agent} do
      {:ok, final, []} =
        BasicAgent.cmd(
          agent,
          {DeregisterAction, %{action_module: UnknownModule}},
          %{}
        )

      # Verify actions unchanged
      assert final.actions == agent.actions
    end

    test "prevents deregistering self", %{agent: agent} do
      {:error, error} =
        BasicAgent.cmd(
          agent,
          {DeregisterAction, %{action_module: DeregisterAction}},
          %{}
        )

      assert error.message == :cannot_deregister_self
    end
  end
end
