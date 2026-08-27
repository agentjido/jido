defmodule JidoTest.Agent.StrategyStateTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Strategy.State, as: StratState

  defp new_agent(attrs) do
    definition = Agent.new!(name: "strategy_state_test_agent", plugin_defaults: :none)
    Agent.instantiate(definition, attrs)
  end

  describe "key/0" do
    test "returns :__strategy__" do
      assert StratState.key() == :__strategy__
    end
  end

  describe "get/2" do
    test "returns default when no strategy state" do
      {:ok, agent} = new_agent(%{id: "test"})
      assert StratState.get(agent) == %{}
      assert StratState.get(agent, %{foo: :bar}) == %{foo: :bar}
    end

    test "returns strategy state when present" do
      {:ok, agent} = new_agent(%{id: "test", state: %{__strategy__: %{status: :running}}})
      assert StratState.get(agent) == %{status: :running}
    end
  end

  describe "put/2" do
    test "writes under __strategy__ key" do
      {:ok, agent} = new_agent(%{id: "test", state: %{other: :value}})
      updated = StratState.put(agent, %{status: :running})
      assert updated.state.__strategy__ == %{status: :running}
      assert updated.state.other == :value
    end

    test "replaces existing strategy state" do
      {:ok, agent} = new_agent(%{id: "test", state: %{__strategy__: %{old: :data}}})
      updated = StratState.put(agent, %{new: :data})
      assert updated.state.__strategy__ == %{new: :data}
      refute Map.has_key?(updated.state.__strategy__, :old)
    end
  end

  describe "update/2" do
    test "updates strategy state using a function" do
      {:ok, agent} = new_agent(%{id: "test", state: %{__strategy__: %{count: 1}}})
      updated = StratState.update(agent, fn state -> Map.put(state, :count, state.count + 1) end)
      assert updated.state.__strategy__.count == 2
    end

    test "works with empty initial state" do
      {:ok, agent} = new_agent(%{id: "test"})
      updated = StratState.update(agent, fn state -> Map.put(state, :initialized, true) end)
      assert updated.state.__strategy__.initialized == true
    end
  end

  describe "status/1" do
    test "returns :idle by default" do
      {:ok, agent} = new_agent(%{id: "test"})
      assert StratState.status(agent) == :idle
    end

    test "returns stored status" do
      {:ok, agent} = new_agent(%{id: "test", state: %{__strategy__: %{status: :success}}})
      assert StratState.status(agent) == :success
    end
  end

  describe "set_status/2" do
    test "sets the strategy status" do
      {:ok, agent} = new_agent(%{id: "test"})
      updated = StratState.set_status(agent, :running)
      assert StratState.status(updated) == :running
    end

    test "preserves other strategy state" do
      {:ok, agent} = new_agent(%{id: "test", state: %{__strategy__: %{data: :kept}}})
      updated = StratState.set_status(agent, :success)
      assert updated.state.__strategy__.data == :kept
      assert updated.state.__strategy__.status == :success
    end

    test "only accepts valid status atoms" do
      {:ok, agent} = new_agent(%{id: "test"})

      for status <- [:idle, :running, :waiting, :success, :failure] do
        updated = StratState.set_status(agent, status)
        assert StratState.status(updated) == status
      end
    end
  end

  describe "terminal?/1" do
    test "returns true for :success and :failure" do
      {:ok, agent} = new_agent(%{id: "test"})
      assert StratState.terminal?(StratState.set_status(agent, :success)) == true
      assert StratState.terminal?(StratState.set_status(agent, :failure)) == true
    end

    test "returns false for other statuses" do
      {:ok, agent} = new_agent(%{id: "test"})
      assert StratState.terminal?(agent) == false
      assert StratState.terminal?(StratState.set_status(agent, :running)) == false
      assert StratState.terminal?(StratState.set_status(agent, :waiting)) == false
      assert StratState.terminal?(StratState.set_status(agent, :idle)) == false
    end
  end

  describe "active?/1" do
    test "returns true for :running and :waiting" do
      {:ok, agent} = new_agent(%{id: "test"})
      assert StratState.active?(StratState.set_status(agent, :running)) == true
      assert StratState.active?(StratState.set_status(agent, :waiting)) == true
    end

    test "returns false for non-active statuses" do
      {:ok, agent} = new_agent(%{id: "test"})
      assert StratState.active?(agent) == false
      assert StratState.active?(StratState.set_status(agent, :idle)) == false
      assert StratState.active?(StratState.set_status(agent, :success)) == false
      assert StratState.active?(StratState.set_status(agent, :failure)) == false
    end
  end

  describe "clear/1" do
    test "resets strategy state to empty map" do
      {:ok, agent} =
        new_agent(%{id: "test", state: %{__strategy__: %{status: :running}, other: :value}})

      cleared = StratState.clear(agent)
      assert cleared.state.__strategy__ == %{}
      assert cleared.state.other == :value
    end
  end
end
