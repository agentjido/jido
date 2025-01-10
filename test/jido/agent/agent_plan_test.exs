defmodule JidoTest.AgentPlanTest do
  use ExUnit.Case, async: true

  alias JidoTest.TestAgents.{BasicAgent, FullFeaturedAgent}
  alias JidoTest.TestActions.{BasicAction, NoSchema}

  describe "plan/3" do
    setup do
      agent = BasicAgent.new()
      {:ok, agent: agent}
    end

    test "plans single action with params and context", %{agent: agent} do
      context = %{user_id: "123", request_id: "abc"}
      {:ok, planned} = BasicAgent.plan(agent, {BasicAction, %{value: 42}}, context)
      assert :queue.len(planned.pending_instructions) == 1
      [instruction] = :queue.to_list(planned.pending_instructions)
      assert instruction.params == %{value: 42}
      assert instruction.context == context
      assert instruction.context.user_id == "123"
      assert instruction.context.request_id == "abc"
      assert instruction.action == BasicAction
      assert planned.dirty_state? == true
    end

    test "plans single action with empty params and context", %{agent: agent} do
      context = %{user_id: "123", request_id: "abc"}
      {:ok, planned} = BasicAgent.plan(agent, {BasicAction, %{}}, context)
      [instruction] = :queue.to_list(planned.pending_instructions)
      assert instruction.params == %{}
      assert instruction.context == context
      assert instruction.context.user_id == "123"
      assert instruction.context.request_id == "abc"
      assert instruction.action == BasicAction
      assert planned.dirty_state? == true
    end

    test "handles unregistered actions", %{agent: agent} do
      assert {:error, error} = BasicAgent.plan(agent, UnregisteredAction, %{})
      assert error.type == :config_error

      assert error.message =~
               "Action: Elixir.UnregisteredAction not registered with agent basic_agent"
    end

    test "preserves existing instructions when planning new ones", %{agent: agent} do
      context = %{user_id: "123", request_id: "abc"}
      {:ok, agent_with_one} = BasicAgent.plan(agent, {BasicAction, %{value: 1}}, context)
      {:ok, agent_with_two} = BasicAgent.plan(agent_with_one, {NoSchema, %{value: 2}}, context)

      instructions = :queue.to_list(agent_with_two.pending_instructions)
      assert length(instructions) == 2

      [first, second] = instructions
      assert first.action == BasicAction
      assert first.params == %{value: 1}
      assert first.context == context
      assert first.context.user_id == "123"
      assert first.context.request_id == "abc"
      assert second.action == NoSchema
      assert second.params == %{value: 2}
      assert second.context == context
      assert second.context.user_id == "123"
      assert second.context.request_id == "abc"
    end

    test "plans list of action tuples with params and context", %{agent: agent} do
      actions = [
        {BasicAction, %{value: 10}},
        {NoSchema, %{value: 2}}
      ]

      context = %{user_id: "123", request_id: "abc"}

      {:ok, planned} = BasicAgent.plan(agent, actions, context)

      [basic, no_schema] = :queue.to_list(planned.pending_instructions)
      assert basic.action == BasicAction
      assert basic.params == %{value: 10}
      assert basic.context == context
      assert basic.context.user_id == "123"
      assert basic.context.request_id == "abc"
      assert no_schema.action == NoSchema
      assert no_schema.params == %{value: 2}
      assert no_schema.context == context
      assert no_schema.context.user_id == "123"
      assert no_schema.context.request_id == "abc"
      assert planned.dirty_state? == true
    end

    test "plans list of action modules with context", %{agent: agent} do
      actions = [BasicAction, NoSchema]
      context = %{user_id: "123", request_id: "abc"}
      {:ok, planned} = BasicAgent.plan(agent, actions, context)

      [basic, no_schema] = :queue.to_list(planned.pending_instructions)
      assert basic.action == BasicAction
      assert basic.params == %{}
      assert basic.context == context
      assert basic.context.user_id == "123"
      assert basic.context.request_id == "abc"
      assert no_schema.action == NoSchema
      assert no_schema.params == %{}
      assert no_schema.context == context
      assert no_schema.context.user_id == "123"
      assert no_schema.context.request_id == "abc"
      assert planned.dirty_state? == true
    end

    test "plans mixed list of modules and tuples with context", %{agent: agent} do
      actions = [
        BasicAction,
        {NoSchema, %{value: 2}}
      ]

      context = %{user_id: "123", request_id: "abc"}

      {:ok, planned} = BasicAgent.plan(agent, actions, context)

      [basic, no_schema] = :queue.to_list(planned.pending_instructions)
      assert basic.action == BasicAction
      assert basic.params == %{}
      assert basic.context == context
      assert basic.context.user_id == "123"
      assert basic.context.request_id == "abc"
      assert no_schema.action == NoSchema
      assert no_schema.params == %{value: 2}
      assert no_schema.context == context
      assert no_schema.context.user_id == "123"
      assert no_schema.context.request_id == "abc"
    end

    test "handles unregistered actions in list", %{agent: agent} do
      actions = [
        BasicAction,
        UnregisteredAction
      ]

      assert {:error, error} = BasicAgent.plan(agent, actions, %{})
      assert error.type == :config_error
      assert error.message =~ "Action not registered"
    end

    test "handles invalid action format in list", %{agent: agent} do
      actions = [
        BasicAction,
        {NoSchema, "invalid"}
      ]

      assert {:error, error} = BasicAgent.plan(agent, actions, %{})
      assert error.type == :execution_error
      assert error.message =~ "Invalid params format."
    end

    test "preserves existing instructions when planning list", %{agent: agent} do
      context = %{user_id: "123", request_id: "abc"}
      {:ok, agent_with_one} = BasicAgent.plan(agent, {BasicAction, %{value: 1}}, context)

      {:ok, agent_with_more} =
        BasicAgent.plan(
          agent_with_one,
          [
            {NoSchema, %{value: 2}},
            BasicAction
          ],
          context
        )

      instructions = :queue.to_list(agent_with_more.pending_instructions)
      assert length(instructions) == 3

      [first, second, third] = instructions
      assert first.action == BasicAction
      assert first.params == %{value: 1}
      assert first.context == context
      assert first.context.user_id == "123"
      assert first.context.request_id == "abc"
      assert second.action == NoSchema
      assert second.params == %{value: 2}
      assert second.context == context
      assert second.context.user_id == "123"
      assert second.context.request_id == "abc"
      assert third.action == BasicAction
      assert third.params == %{}
      assert third.context == context
      assert third.context.user_id == "123"
      assert third.context.request_id == "abc"
    end

    test "handles empty list of actions", %{agent: agent} do
      assert {:ok, planned} = BasicAgent.plan(agent, [], %{})
      assert :queue.len(planned.pending_instructions) == 0
      # Verify state is still marked dirty
      assert planned.dirty_state? == true
    end

    test "handles nil context", %{agent: agent} do
      {:ok, planned} = BasicAgent.plan(agent, BasicAction, nil)
      [instruction] = :queue.to_list(planned.pending_instructions)
      # Verify empty map is used
      assert instruction.context == %{}
    end

    test "preserves existing context when planning additional actions", %{agent: agent} do
      {:ok, agent_with_one} = BasicAgent.plan(agent, BasicAction, %{request_id: "123"})
      {:ok, agent_with_two} = BasicAgent.plan(agent_with_one, NoSchema, %{user_id: "456"})

      [first, second] = :queue.to_list(agent_with_two.pending_instructions)
      assert first.context.request_id == "123"
      assert second.context.user_id == "456"
    end

    test "validates params are maps", %{agent: agent} do
      assert {:error, error} = BasicAgent.plan(agent, {BasicAction, ["invalid"]}, %{})
      assert error.type == :execution_error
    end

    test "handles nil params", %{agent: agent} do
      {:ok, planned} = BasicAgent.plan(agent, {BasicAction, nil}, %{})
      [instruction] = :queue.to_list(planned.pending_instructions)
      assert instruction.params == %{}
    end

    test "handles deeply nested action lists", %{agent: agent} do
      actions = [
        BasicAction,
        [NoSchema, BasicAction],
        [{NoSchema, %{value: 1}}, BasicAction]
      ]

      assert {:error, error} = BasicAgent.plan(agent, actions, %{})
      assert error.type == :execution_error
      assert error.message =~ "Invalid instruction format"
    end

    test "preserves agent state when planning fails", %{agent: agent} do
      original_state = agent.state
      {:ok, agent_with_one} = BasicAgent.plan(agent, BasicAction, %{})

      assert {:error, _} = BasicAgent.plan(agent_with_one, UnregisteredAction, %{})
      assert agent_with_one.state == original_state
    end

    test "handles large number of actions", %{agent: agent} do
      actions = List.duplicate(BasicAction, 1000)
      {:ok, planned} = BasicAgent.plan(agent, actions, %{})
      assert :queue.len(planned.pending_instructions) == 1000
    end

    test "executes on_before_plan callback once per plan call" do
      agent = JidoTest.TestAgents.CallbackTrackingAgent.new()

      actions = [
        JidoTest.TestActions.Add,
        JidoTest.TestActions.Multiply,
        JidoTest.TestActions.Add
      ]

      {:ok, planned} = JidoTest.TestAgents.CallbackTrackingAgent.plan(agent, actions, %{})

      # Verify only one on_before_plan callback was executed
      total_callbacks =
        planned.state.callback_count
        |> Enum.reduce(0, fn
          {{:on_before_plan, _action}, count}, acc -> acc + count
          _, acc -> acc
        end)

      assert total_callbacks == 1
    end

    test "tracks callback execution order" do
      agent = JidoTest.TestAgents.CallbackTrackingAgent.new()

      actions = [
        JidoTest.TestActions.Add,
        JidoTest.TestActions.Multiply
      ]

      {:ok, planned} = JidoTest.TestAgents.CallbackTrackingAgent.plan(agent, actions, %{})

      # Verify callback log order
      log = planned.state.callback_log
      assert length(log) == 1

      [callback_entry] = log
      assert callback_entry.callback == {:on_before_plan, nil}
    end

    test "maintains callback state between multiple plan calls" do
      agent = JidoTest.TestAgents.CallbackTrackingAgent.new()

      # First plan
      {:ok, agent_with_one} =
        JidoTest.TestAgents.CallbackTrackingAgent.plan(
          agent,
          JidoTest.TestActions.Add,
          %{}
        )

      # Second plan
      {:ok, agent_with_two} =
        JidoTest.TestAgents.CallbackTrackingAgent.plan(
          agent_with_one,
          JidoTest.TestActions.Multiply,
          %{}
        )

      # Verify we have two on_before_plan callbacks recorded (one per plan call)
      counts = agent_with_two.state.callback_count
      assert counts[{:on_before_plan, nil}] == 2

      # Verify log maintains history of both callbacks
      log = agent_with_two.state.callback_log
      assert length(log) == 2
    end

    test "handles concurrent planning operations safely", %{agent: agent} do
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            BasicAgent.plan(agent, {BasicAction, %{value: i}}, %{})
          end)
        end

      results = Task.await_many(tasks)
      assert Enum.all?(results, fn {:ok, _} -> true end)
    end

    test "maintains queue order with mixed action formats", %{agent: agent} do
      actions = [
        BasicAction,
        {NoSchema, %{value: 1}},
        BasicAction,
        {BasicAction, %{}}
      ]

      {:ok, planned} = BasicAgent.plan(agent, actions, %{})
      instructions = :queue.to_list(planned.pending_instructions)

      assert length(instructions) == 4

      assert Enum.map(instructions, & &1.action) == [
               BasicAction,
               NoSchema,
               BasicAction,
               BasicAction
             ]
    end

    test "handles boundary values in params", %{agent: agent} do
      params = %{
        # Max 64-bit integer
        integer: Integer.pow(2, 63) - 1,
        # Max float
        float: 1.0e308,
        # Large string
        string: String.duplicate("a", 1_000_000)
      }

      {:ok, planned} = BasicAgent.plan(agent, {BasicAction, params}, %{})
      [instruction] = :queue.to_list(planned.pending_instructions)
      assert instruction.params == params
    end

    test "prevents calling plan with wrong agent module" do
      agent = FullFeaturedAgent.new()
      assert {:error, error} = BasicAgent.plan(agent, BasicAction, %{})
      assert error.type == :validation_error

      assert error.message =~
               "Invalid agent type. Expected #{FullFeaturedAgent}, got #{BasicAgent}"
    end
  end
end
