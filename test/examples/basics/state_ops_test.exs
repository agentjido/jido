defmodule JidoExampleTest.StateOpsTest do
  @moduledoc """
  Example test demonstrating StateOps: SetState, ReplaceState, DeleteKeys, SetPath, DeletePath.

  This test shows:
  - How actions can return StateOps alongside results
  - The difference between SetState (merge) and ReplaceState (overwrite)
  - How DeleteKeys removes top-level keys
  - How SetPath/DeletePath handle nested state updates

  Run with: mix test --include example
  """
  use JidoTest.Case, async: true

  @moduletag :example
  @moduletag timeout: 10_000

  alias Jido.Agent.StateOp

  # ===========================================================================
  # ACTIONS: Demonstrate different StateOps
  # ===========================================================================

  defmodule MergeMetadataAction do
    @moduledoc false
    use Jido.Action,
      name: "merge_metadata",
      schema: [
        metadata: [type: :map, required: true]
      ]

    def run(%{metadata: metadata}, _context) do
      {:ok, %{}, %StateOp.SetState{attrs: %{metadata: metadata}}}
    end
  end

  defmodule ReplaceAllAction do
    @moduledoc false
    use Jido.Action,
      name: "replace_all",
      schema: [
        new_state: [type: :map, required: true]
      ]

    def run(%{new_state: new_state}, _context) do
      {:ok, %{}, %StateOp.ReplaceState{state: new_state}}
    end
  end

  defmodule ClearTempDataAction do
    @moduledoc false
    use Jido.Action,
      name: "clear_temp_data",
      schema: []

    def run(_params, _context) do
      {:ok, %{}, %StateOp.DeleteKeys{keys: [:temp, :cache]}}
    end
  end

  defmodule SetNestedValueAction do
    @moduledoc false
    use Jido.Action,
      name: "set_nested_value",
      schema: [
        path: [type: {:list, :atom}, required: true],
        value: [type: :any, required: true]
      ]

    def run(%{path: path, value: value}, _context) do
      {:ok, %{}, %StateOp.SetPath{path: path, value: value}}
    end
  end

  defmodule DeleteNestedValueAction do
    @moduledoc false
    use Jido.Action,
      name: "delete_nested_value",
      schema: [
        path: [type: {:list, :atom}, required: true]
      ]

    def run(%{path: path}, _context) do
      {:ok, %{}, %StateOp.DeletePath{path: path}}
    end
  end

  defmodule ComboAction do
    @moduledoc false
    use Jido.Action,
      name: "combo_action",
      schema: []

    def run(_params, _context) do
      {:ok, %{primary_result: "done"},
       [
         %StateOp.SetState{attrs: %{step: :completed}},
         %StateOp.DeleteKeys{keys: [:temp]}
       ]}
    end
  end

  # ===========================================================================
  # AGENT: Flexible schema for testing state ops
  # ===========================================================================

  defmodule FlexAgent do
    @moduledoc false
    use Jido.Agent,
      name: "flex_agent",
      schema: [
        counter: [type: :integer, default: 0],
        name: [type: :string, default: ""],
        metadata: [type: :map, default: %{}],
        temp: [type: :any, default: nil],
        cache: [type: :any, default: nil],
        config: [type: :map, default: %{}],
        step: [type: :atom, default: :idle]
      ]
  end

  # ===========================================================================
  # TESTS
  # ===========================================================================

  describe "SetState (deep merge)" do
    test "SetState merges into existing state without overwriting other keys" do
      agent = FlexAgent.new(state: %{counter: 10, name: "test"})

      {agent, []} =
        FlexAgent.cmd(agent, {MergeMetadataAction, %{metadata: %{version: "1.0"}}})

      assert agent.state.counter == 10
      assert agent.state.name == "test"
      assert agent.state.metadata == %{version: "1.0"}
    end

    test "SetState deep merges nested maps" do
      agent = FlexAgent.new(state: %{metadata: %{author: "alice", tags: ["elixir"]}})

      {agent, []} =
        FlexAgent.cmd(agent, {MergeMetadataAction, %{metadata: %{version: "2.0"}}})

      assert agent.state.metadata.author == "alice"
      assert agent.state.metadata.version == "2.0"
    end
  end

  describe "ReplaceState (wholesale replacement)" do
    test "ReplaceState overwrites entire state" do
      agent = FlexAgent.new(state: %{counter: 100, name: "old-name", metadata: %{foo: "bar"}})

      {agent, []} =
        FlexAgent.cmd(
          agent,
          {ReplaceAllAction, %{new_state: %{counter: 0, name: "fresh", step: :reset}}}
        )

      assert agent.state.counter == 0
      assert agent.state.name == "fresh"
      assert agent.state.step == :reset
      refute Map.has_key?(agent.state, :metadata)
    end
  end

  describe "DeleteKeys (remove top-level keys)" do
    test "DeleteKeys removes specified keys" do
      agent = FlexAgent.new(state: %{counter: 5, temp: "temporary", cache: %{data: 123}})

      {agent, []} = FlexAgent.cmd(agent, ClearTempDataAction)

      assert agent.state.counter == 5
      refute Map.has_key?(agent.state, :temp)
      refute Map.has_key?(agent.state, :cache)
    end

    test "DeleteKeys is idempotent for missing keys" do
      agent = FlexAgent.new(state: %{counter: 5})

      {agent, []} = FlexAgent.cmd(agent, ClearTempDataAction)

      assert agent.state.counter == 5
    end
  end

  describe "SetPath (nested updates)" do
    test "SetPath sets value at nested path" do
      agent = FlexAgent.new(config: %{})

      {agent, []} =
        FlexAgent.cmd(
          agent,
          {SetNestedValueAction, %{path: [:config, :timeout], value: 5000}}
        )

      assert agent.state.config.timeout == 5000
    end

    test "SetPath creates intermediate maps if needed" do
      agent = FlexAgent.new(config: %{})

      {agent, []} =
        FlexAgent.cmd(
          agent,
          {SetNestedValueAction, %{path: [:config, :database, :host], value: "localhost"}}
        )

      assert agent.state.config.database.host == "localhost"
    end

    test "SetPath preserves sibling keys" do
      agent = FlexAgent.new(state: %{config: %{timeout: 1000, retries: 3}})

      {agent, []} =
        FlexAgent.cmd(
          agent,
          {SetNestedValueAction, %{path: [:config, :timeout], value: 5000}}
        )

      assert agent.state.config.timeout == 5000
      assert agent.state.config.retries == 3
    end
  end

  describe "DeletePath (nested deletion)" do
    test "DeletePath removes value at nested path" do
      agent = FlexAgent.new(state: %{config: %{timeout: 1000, secret: "password"}})

      {agent, []} =
        FlexAgent.cmd(
          agent,
          {DeleteNestedValueAction, %{path: [:config, :secret]}}
        )

      assert agent.state.config.timeout == 1000
      refute Map.has_key?(agent.state.config, :secret)
    end
  end

  describe "combining StateOps with results" do
    test "action can return result map AND state ops" do
      agent = FlexAgent.new(state: %{temp: "will be deleted"})

      {agent, []} = FlexAgent.cmd(agent, ComboAction)

      assert agent.state.primary_result == "done"
      assert agent.state.step == :completed
      refute Map.has_key?(agent.state, :temp)
    end
  end
end
