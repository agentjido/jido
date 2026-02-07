defmodule JidoExampleTest.CounterAgentTest do
  @moduledoc """
  Example test demonstrating basic agent patterns: cmd/2, action schemas, pure state updates.

  This is the simplest possible Jido agent example, showing:
  - How to define an agent with a schema
  - How to define actions with validated parameters
  - How cmd/2 returns an updated immutable agent
  - That pure state updates produce no directives

  Run with: mix test --include example
  """
  use JidoTest.Case, async: true

  @moduletag :example
  @moduletag timeout: 10_000

  # ===========================================================================
  # ACTIONS: Pure state transformations
  # ===========================================================================

  defmodule IncrementAction do
    @moduledoc false
    use Jido.Action,
      name: "increment",
      schema: [
        amount: [type: :integer, default: 1]
      ]

    def run(%{amount: amount}, context) do
      current = Map.get(context.state, :counter, 0)
      {:ok, %{counter: current + amount}}
    end
  end

  defmodule DecrementAction do
    @moduledoc false
    use Jido.Action,
      name: "decrement",
      schema: [
        amount: [type: :integer, default: 1]
      ]

    def run(%{amount: amount}, context) do
      current = Map.get(context.state, :counter, 0)
      {:ok, %{counter: current - amount}}
    end
  end

  defmodule ResetAction do
    @moduledoc false
    use Jido.Action,
      name: "reset",
      schema: []

    def run(_params, _context) do
      {:ok, %{counter: 0}}
    end
  end

  # ===========================================================================
  # AGENT: Simple counter with typed schema
  # ===========================================================================

  defmodule CounterAgent do
    @moduledoc false
    use Jido.Agent,
      name: "counter_agent",
      description: "A simple counter demonstrating cmd/2 basics",
      schema: [
        counter: [type: :integer, default: 0],
        name: [type: :string, default: "unnamed"]
      ]
  end

  # ===========================================================================
  # TESTS
  # ===========================================================================

  describe "agent basics" do
    test "agent starts with default schema values" do
      agent = CounterAgent.new()

      assert agent.state.counter == 0
      assert agent.state.name == "unnamed"
    end

    test "agent can be created with initial state" do
      agent = CounterAgent.new(state: %{counter: 10, name: "my-counter"})

      assert agent.state.counter == 10
      assert agent.state.name == "my-counter"
    end
  end

  describe "cmd/2 basics" do
    test "cmd/2 returns updated immutable agent" do
      agent = CounterAgent.new()

      {updated_agent, directives} = CounterAgent.cmd(agent, {IncrementAction, %{amount: 5}})

      assert updated_agent.state.counter == 5
      assert directives == []
      assert agent.state.counter == 0
    end

    test "cmd/2 with default action params" do
      agent = CounterAgent.new(state: %{counter: 10})

      {updated_agent, _directives} = CounterAgent.cmd(agent, IncrementAction)

      assert updated_agent.state.counter == 11
    end

    test "multiple cmd/2 calls chain state updates" do
      agent = CounterAgent.new()

      {agent, []} = CounterAgent.cmd(agent, {IncrementAction, %{amount: 10}})
      {agent, []} = CounterAgent.cmd(agent, {IncrementAction, %{amount: 5}})
      {agent, []} = CounterAgent.cmd(agent, {DecrementAction, %{amount: 3}})

      assert agent.state.counter == 12
    end

    test "cmd/2 with list of actions executes all in sequence" do
      agent = CounterAgent.new()

      {agent, directives} =
        CounterAgent.cmd(agent, [
          {IncrementAction, %{amount: 10}},
          {IncrementAction, %{amount: 5}},
          {DecrementAction, %{amount: 2}}
        ])

      assert agent.state.counter == 13
      assert directives == []
    end

    test "reset action restores default value" do
      agent = CounterAgent.new(state: %{counter: 100})

      {agent, []} = CounterAgent.cmd(agent, ResetAction)

      assert agent.state.counter == 0
    end
  end

  describe "action schema validation" do
    test "action with valid params succeeds" do
      agent = CounterAgent.new()

      {agent, []} = CounterAgent.cmd(agent, {IncrementAction, %{amount: 42}})

      assert agent.state.counter == 42
    end

    test "action uses default when param omitted" do
      agent = CounterAgent.new()

      {agent, []} = CounterAgent.cmd(agent, {IncrementAction, %{}})

      assert agent.state.counter == 1
    end
  end
end
