defmodule JidoTest.AgentTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias JidoTest.TestActions
  alias JidoTest.TestAgents

  describe "module definition" do
    test "defines metadata accessors" do
      assert TestAgents.Basic.name() == "basic_agent"
      assert TestAgents.Basic.description() == "A basic test agent"
      assert TestAgents.Basic.category() == "test"
      assert TestAgents.Basic.tags() == ["test", "basic"]
      assert TestAgents.Basic.vsn() == "1.0.0"
    end

    test "minimal agent has default values" do
      assert TestAgents.Minimal.name() == "minimal_agent"
      assert TestAgents.Minimal.description() == nil
      schema = TestAgents.Minimal.schema()
      assert is_struct(schema) or schema == []
    end
  end

  describe "new/1" do
    test "creates agent with auto-generated id" do
      agent = TestAgents.Minimal.new()
      assert is_binary(agent.id)
      assert String.length(agent.id) > 0
    end

    test "creates agent with custom id" do
      agent = TestAgents.Minimal.new(id: "custom-123")
      assert agent.id == "custom-123"
    end

    test "creates agent with initial state" do
      agent = TestAgents.Basic.new(state: %{counter: 10})
      assert agent.state.counter == 10
      assert agent.state.status == :idle
    end

    test "applies schema defaults to state" do
      agent = TestAgents.Basic.new()
      assert agent.state.counter == 0
      assert agent.state.status == :idle
    end

    test "merges initial state with defaults" do
      agent = TestAgents.Basic.new(state: %{counter: 5})
      assert agent.state.counter == 5
      assert agent.state.status == :idle
    end

    test "populates agent metadata" do
      agent = TestAgents.Basic.new()
      assert agent.name == "basic_agent"
      assert agent.description == "A basic test agent"
      assert agent.category == "test"
      assert agent.tags == ["test", "basic"]
      assert agent.vsn == "1.0.0"
    end

    test "uses default strategy" do
      assert TestAgents.Basic.strategy() == Jido.Agent.Strategy.Direct
      assert TestAgents.Basic.strategy_opts() == []
    end
  end

  describe "new/1 strategy initialization" do
    test "new/1 calls strategy.init/2 for state initialization" do
      # For agents with custom strategies that modify state in init,
      # new/1 should apply those state changes
      agent = TestAgents.WithCustomStrategy.new()
      assert agent.state.__strategy__.initialized == true
    end

    test "new/1 returns just the agent (directives are dropped)" do
      # new/1 returns Agent.t(), not {Agent.t(), directives}
      agent = TestAgents.WithCustomStrategy.new()
      assert %Agent{} = agent
    end

    test "strategy init is idempotent - can be called again by AgentServer" do
      # This simulates what AgentServer does: create via new/1 then call init again
      agent = TestAgents.WithCustomStrategy.new()
      assert agent.state.__strategy__.initialized == true

      # Calling strategy.init again should be safe (idempotent)
      ctx = %{agent_module: TestAgents.WithCustomStrategy, strategy_opts: []}
      {agent2, directives} = TestAgents.InitDirectiveStrategy.init(agent, ctx)

      # State should still be initialized
      assert agent2.state.__strategy__.initialized == true
      # Directives should still be emitted (for AgentServer to process)
      assert length(directives) == 1
    end
  end

  describe "set/2" do
    test "updates state with map" do
      agent = TestAgents.Basic.new()
      {:ok, updated} = TestAgents.Basic.set(agent, %{counter: 42})
      assert updated.state.counter == 42
    end

    test "updates state with keyword list" do
      agent = TestAgents.Basic.new()
      {:ok, updated} = TestAgents.Basic.set(agent, counter: 42, status: :running)
      assert updated.state.counter == 42
      assert updated.state.status == :running
    end

    test "deep merges nested maps" do
      agent = TestAgents.Basic.new(state: %{config: %{a: 1, b: 2}})
      {:ok, updated} = TestAgents.Basic.set(agent, %{config: %{b: 3, c: 4}})
      assert updated.state.config == %{a: 1, b: 3, c: 4}
    end
  end

  describe "validate/2" do
    test "validates state against schema" do
      agent = TestAgents.Basic.new()
      {:ok, validated} = TestAgents.Basic.validate(agent)
      assert validated.state.counter == 0
      assert validated.state.status == :idle
    end

    test "preserves extra fields in non-strict mode" do
      agent = TestAgents.Basic.new(state: %{counter: 0, extra_field: "hello"})
      {:ok, validated} = TestAgents.Basic.validate(agent)
      assert validated.state.extra_field == "hello"
    end

    test "strict mode only keeps schema fields" do
      agent = TestAgents.Basic.new(state: %{counter: 0, status: :idle, extra_field: "hello"})
      {:ok, validated} = TestAgents.Basic.validate(agent, strict: true)
      refute Map.has_key?(validated.state, :extra_field)
    end
  end

  describe "cmd/2" do
    test "executes action module" do
      agent = TestAgents.Basic.new()
      {updated, _directives} = TestAgents.Basic.cmd(agent, TestActions.NoSchema)
      assert updated.state.result == "No params"
    end

    test "executes action tuple" do
      agent = TestAgents.Basic.new()

      {updated, _directives} =
        TestAgents.Basic.cmd(agent, {TestActions.BasicAction, %{value: 42}})

      assert updated.state.value == 42
    end

    test "executes list of actions" do
      agent = TestAgents.Basic.new()

      {updated, directives} =
        TestAgents.Basic.cmd(agent, [
          {TestActions.Add, %{value: 5, amount: 3}},
          TestActions.NoSchema
        ])

      assert updated.state.value == 8
      assert updated.state.result == "No params"
      assert directives == []
    end

    test "handles %Instruction{} struct directly" do
      agent = TestAgents.Basic.new()

      {:ok, instruction} =
        Jido.Instruction.new(%{action: TestActions.BasicAction, params: %{value: 99}})

      {updated, _directives} = TestAgents.Basic.cmd(agent, instruction)
      assert updated.state.value == 99
    end

    test "emits error directive for invalid action params" do
      agent = TestAgents.Basic.new()
      {_agent, directives} = TestAgents.Basic.cmd(agent, {TestActions.BasicAction, %{}})

      assert [%Jido.Agent.Directive.Error{context: :instruction, error: error}] = directives
      assert error.message == "Instruction failed"
    end

    test "invalid input format returns error directive" do
      agent = TestAgents.Basic.new()
      {updated, directives} = TestAgents.Basic.cmd(agent, {:unknown, "whatever"})

      assert updated.state == agent.state
      assert [%Jido.Agent.Directive.Error{context: :normalize}] = directives
    end
  end

  describe "cmd/3 with opts" do
    test "passes timeout option to instruction" do
      agent = TestAgents.Basic.new()

      {_updated, directives} =
        TestAgents.Basic.cmd(agent, {TestActions.SlowAction, %{delay_ms: 200}}, timeout: 10)

      assert [%Jido.Agent.Directive.Error{error: error}] = directives
      assert error.message == "Instruction failed"
    end

    test "passes max_retries option to disable retries" do
      agent = TestAgents.Basic.new()

      start_time = System.monotonic_time(:millisecond)

      {_updated, directives} =
        TestAgents.Basic.cmd(
          agent,
          {TestActions.SlowAction, %{delay_ms: 200}},
          timeout: 10,
          max_retries: 0
        )

      elapsed = System.monotonic_time(:millisecond) - start_time

      assert [%Jido.Agent.Directive.Error{}] = directives
      assert elapsed < 1_000
    end

    test "cmd/2 delegates to cmd/3 with empty opts" do
      agent = TestAgents.Basic.new()

      {updated1, directives1} = TestAgents.Basic.cmd(agent, TestActions.NoSchema)
      {updated2, directives2} = TestAgents.Basic.cmd(agent, TestActions.NoSchema, [])

      assert updated1.state == updated2.state
      assert directives1 == directives2
    end

    test "opts are merged into all instructions in a list" do
      agent = TestAgents.Basic.new()

      {_updated, directives} =
        TestAgents.Basic.cmd(
          agent,
          [
            {TestActions.SlowAction, %{delay_ms: 200}},
            {TestActions.SlowAction, %{delay_ms: 200}}
          ],
          timeout: 10,
          max_retries: 0
        )

      assert [%Jido.Agent.Directive.Error{}, %Jido.Agent.Directive.Error{}] = directives
    end
  end

  describe "lifecycle hooks" do
    test "on_after_cmd is called after processing" do
      agent = TestAgents.Hook.new()
      refute Map.has_key?(agent.state, :hook_called)

      {updated, _} = TestAgents.Hook.cmd(agent, TestActions.NoSchema)
      assert updated.state.hook_called == true
    end
  end

  describe "strategy" do
    test "default strategy is Direct" do
      assert TestAgents.Basic.strategy() == Jido.Agent.Strategy.Direct
      assert TestAgents.Basic.strategy_opts() == []
    end

    test "custom strategy module is used" do
      assert TestAgents.CustomStrategy.strategy() == TestAgents.CountingStrategy
      assert TestAgents.CustomStrategy.strategy_opts() == []
    end

    test "strategy with options extracts module and opts" do
      assert TestAgents.StrategyWithOpts.strategy() == TestAgents.CountingStrategy
      assert TestAgents.StrategyWithOpts.strategy_opts() == [max_depth: 5]
    end

    test "custom strategy is invoked during cmd/2" do
      agent = TestAgents.CustomStrategy.new()
      refute Map.has_key?(agent.state, :strategy_count)

      {updated, _} = TestAgents.CustomStrategy.cmd(agent, TestActions.NoSchema)
      assert updated.state.strategy_count == 1

      {updated2, _} = TestAgents.CustomStrategy.cmd(updated, TestActions.NoSchema)
      assert updated2.state.strategy_count == 2
    end
  end

  describe "base module functions" do
    test "Agent.new/1 creates agent from attrs (map)" do
      {:ok, agent} = Agent.new(%{name: "test_agent", id: "test-123"})
      assert agent.id == "test-123"
      assert agent.name == "test_agent"
    end

    test "Agent.new/1 creates agent from attrs (keyword list)" do
      {:ok, agent} = Agent.new(name: "test_agent", id: "kw-123")
      assert agent.id == "kw-123"
      assert agent.name == "test_agent"
    end

    test "Agent.set/2 updates state" do
      {:ok, agent} = Agent.new(%{id: "test"})
      {:ok, updated} = Agent.set(agent, %{key: "value"})
      assert updated.state.key == "value"
    end

    test "Agent.new/1 returns error for invalid id type" do
      {:error, error} = Agent.new(%{id: 12_345})
      assert error.message == "Agent validation failed"
    end

    test "Agent.new/1 normalizes nil id to generated id" do
      {:ok, agent} = Agent.new(%{id: nil, name: "nil-id-agent"})
      assert is_binary(agent.id)
      assert agent.id != ""
    end

    test "Agent.validate/2 validates state against schema" do
      {:ok, agent} = Agent.new(%{id: "test", schema: [count: [type: :integer, default: 0]]})
      {:ok, validated} = Agent.validate(agent)
      assert validated.state.count == 0
    end

    test "Agent.validate/2 returns error for invalid state" do
      {:ok, agent} = Agent.new(%{id: "test", schema: [count: [type: :integer, required: true]]})
      agent = %{agent | state: %{count: "not_an_integer"}}
      {:error, error} = Agent.validate(agent)
      assert error.message == "State validation failed"
    end

    test "Agent.schema/0 returns the Zoi schema" do
      schema = Agent.schema()
      assert schema
    end

    test "Agent.config_schema/0 returns the agent config schema" do
      schema = Agent.config_schema()
      assert schema
    end
  end

  describe "actions returning effects" do
    test "action can emit signal via directive" do
      agent = TestAgents.Basic.new()
      {updated, directives} = TestAgents.Basic.cmd(agent, TestActions.EmitAction)

      assert updated.state.emitted == true
      assert [%Jido.Agent.Directive.Emit{signal: signal}] = directives
      assert signal.type == "test.emitted"
    end

    test "action can return multiple directives" do
      agent = TestAgents.Basic.new()
      {updated, directives} = TestAgents.Basic.cmd(agent, TestActions.MultiEffectAction)

      assert updated.state.triggered == true
      assert length(directives) == 2
      assert [%Jido.Agent.Directive.Emit{}, %Jido.Agent.Directive.Schedule{}] = directives
    end

    test "StateOp.SetState modifies agent state but is not returned as directive" do
      agent = TestAgents.Basic.new()
      {updated, directives} = TestAgents.Basic.cmd(agent, TestActions.SetStateAction)

      assert updated.state.primary == "result"
      assert updated.state.extra == "state"
      assert directives == []
    end

    test "StateOp.ReplaceState replaces state wholesale" do
      agent = TestAgents.Basic.new(state: %{old: "data", counter: 10})
      {updated, directives} = TestAgents.Basic.cmd(agent, TestActions.ReplaceStateAction)

      assert updated.state == %{replaced: true, fresh: "state"}
      refute Map.has_key?(updated.state, :old)
      refute Map.has_key?(updated.state, :counter)
      assert directives == []
    end

    test "StateOp.DeleteKeys removes top-level keys from state" do
      agent = TestAgents.Basic.new(state: %{to_delete: 1, also_delete: 2, keep: 3})
      {updated, directives} = TestAgents.Basic.cmd(agent, TestActions.DeleteKeysAction)

      refute Map.has_key?(updated.state, :to_delete)
      refute Map.has_key?(updated.state, :also_delete)
      assert updated.state.keep == 3
      assert directives == []
    end

    test "StateOp.SetPath sets value at nested path" do
      agent = TestAgents.Basic.new(state: %{existing: "value"})
      {updated, directives} = TestAgents.Basic.cmd(agent, TestActions.SetPathAction)

      assert updated.state.nested.deep.value == 42
      assert updated.state.existing == "value"
      assert directives == []
    end

    test "StateOp.DeletePath removes value at nested path" do
      agent = TestAgents.Basic.new(state: %{nested: %{to_remove: "gone", keep: "here"}})
      {updated, directives} = TestAgents.Basic.cmd(agent, TestActions.DeletePathAction)

      refute Map.has_key?(updated.state.nested, :to_remove)
      assert updated.state.nested.keep == "here"
      assert directives == []
    end
  end

  describe "Zoi schema support" do
    test "agent works with Zoi schema" do
      agent = TestAgents.ZoiSchema.new()
      assert agent.name == "zoi_schema_agent"
    end

    test "validate works with Zoi schema" do
      agent = TestAgents.ZoiSchema.new(state: %{status: :running, count: 5})
      {:ok, validated} = TestAgents.ZoiSchema.validate(agent)
      assert validated.state.status == :running
      assert validated.state.count == 5
    end
  end

  describe "plugin routes" do
    test "plugin_routes/0 returns expanded routes with prefix" do
      routes = TestAgents.AgentWithPluginRoutes.plugin_routes()

      assert length(routes) == 2
      assert {"test_routes_plugin.post", JidoTest.PluginTestAction, -10} in routes
      assert {"test_routes_plugin.list", JidoTest.PluginTestAction, -10} in routes
    end

    test "multi-instance plugins get unique route prefixes" do
      routes = TestAgents.AgentWithMultiInstancePlugins.plugin_routes()

      assert length(routes) == 4
      assert {"support.test_routes_plugin.post", JidoTest.PluginTestAction, -10} in routes
      assert {"support.test_routes_plugin.list", JidoTest.PluginTestAction, -10} in routes
      assert {"sales.test_routes_plugin.post", JidoTest.PluginTestAction, -10} in routes
      assert {"sales.test_routes_plugin.list", JidoTest.PluginTestAction, -10} in routes
    end

    test "compile-time conflict detection raises error for duplicate routes" do
      assert_raise CompileError, ~r/Route conflict|Duplicate plugin state_keys/, fn ->
        defmodule ConflictAgent do
          use Jido.Agent,
            name: "conflict_agent",
            plugins: [
              TestAgents.TestPluginWithRoutes,
              TestAgents.TestPluginWithRoutes
            ]
        end
      end
    end

    test "no route conflict when plugins use different :as aliases" do
      routes = TestAgents.AgentWithMultiInstancePlugins.plugin_routes()
      assert length(routes) == 4
    end
  end
end
