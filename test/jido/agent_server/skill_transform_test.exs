defmodule JidoTest.AgentServer.SkillTransformTest do
  use JidoTest.Case, async: true

  alias Jido.Signal
  alias JidoTest.WaitHelpers

  # Test action
  defmodule SetValueAction do
    @moduledoc false
    use Jido.Action,
      name: "set_value",
      schema: Zoi.object(%{value: Zoi.integer() |> Zoi.default(42)})

    alias Jido.Agent.Internal

    def run(%{value: value}, _context) do
      {:ok, %{}, %Internal.SetPath{path: [:value], value: value}}
    end
  end

  # Skill with default transform (identity)
  defmodule DefaultTransformSkill do
    @moduledoc false
    use Jido.Skill,
      name: "default_transform",
      state_key: :default_transform,
      actions: [JidoTest.AgentServer.SkillTransformTest.SetValueAction],
      signal_patterns: ["value.*"]
  end

  # Skill that wraps agent with metadata
  defmodule MetadataTransformSkill do
    @moduledoc false
    use Jido.Skill,
      name: "metadata_transform",
      state_key: :metadata_transform,
      actions: [JidoTest.AgentServer.SkillTransformTest.SetValueAction],
      signal_patterns: ["value.*"]

    @impl Jido.Skill
    def transform_result(_action, agent, _context) do
      new_state = Map.put(agent.state, :transformed_by, __MODULE__)
      %{agent | state: new_state}
    end
  end

  # Skill that adds timestamp
  defmodule TimestampTransformSkill do
    @moduledoc false
    use Jido.Skill,
      name: "timestamp_transform",
      state_key: :timestamp_transform,
      actions: [JidoTest.AgentServer.SkillTransformTest.SetValueAction],
      signal_patterns: ["value.*"]

    @impl Jido.Skill
    def transform_result(_action, agent, _context) do
      new_state = Map.put(agent.state, :transformed_at, DateTime.utc_now())
      %{agent | state: new_state}
    end
  end

  # Agent with default transform
  defmodule DefaultTransformAgent do
    @moduledoc false
    use Jido.Agent,
      name: "default_transform_agent",
      schema: [value: [type: :integer, default: 0]],
      skills: [JidoTest.AgentServer.SkillTransformTest.DefaultTransformSkill]

    def signal_routes do
      [{"value.set", JidoTest.AgentServer.SkillTransformTest.SetValueAction}]
    end
  end

  # Agent with metadata transform
  defmodule MetadataTransformAgent do
    @moduledoc false
    use Jido.Agent,
      name: "metadata_transform_agent",
      schema: [value: [type: :integer, default: 0]],
      skills: [JidoTest.AgentServer.SkillTransformTest.MetadataTransformSkill]

    def signal_routes do
      [{"value.set", JidoTest.AgentServer.SkillTransformTest.SetValueAction}]
    end
  end

  # Agent with multiple transform skills (chained)
  defmodule ChainedTransformAgent do
    @moduledoc false
    use Jido.Agent,
      name: "chained_transform_agent",
      schema: [value: [type: :integer, default: 0]],
      skills: [
        JidoTest.AgentServer.SkillTransformTest.MetadataTransformSkill,
        JidoTest.AgentServer.SkillTransformTest.TimestampTransformSkill
      ]

    def signal_routes do
      [{"value.set", JidoTest.AgentServer.SkillTransformTest.SetValueAction}]
    end
  end

  describe "transform_result/3 with default implementation" do
    test "agent returned unchanged when skill uses default transform", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: DefaultTransformAgent, jido: jido)

      signal = Signal.new!("value.set", %{value: 100}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state[:value] == 100
      refute Map.has_key?(agent.state, :transformed_by)
    end
  end

  describe "transform_result/3 with custom implementation" do
    test "skill can add metadata to returned agent", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: MetadataTransformAgent, jido: jido)

      signal = Signal.new!("value.set", %{value: 50}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state[:value] == 50

      assert agent.state[:transformed_by] ==
               JidoTest.AgentServer.SkillTransformTest.MetadataTransformSkill
    end

    test "transform only affects call path, not internal state", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: MetadataTransformAgent, jido: jido)

      signal = Signal.new!("value.set", %{value: 75}, source: "/test")
      {:ok, returned_agent} = Jido.AgentServer.call(pid, signal)

      # Returned agent has transform applied
      assert returned_agent.state[:transformed_by] ==
               JidoTest.AgentServer.SkillTransformTest.MetadataTransformSkill

      # Internal state does NOT have transform (transforms are for caller view only)
      {:ok, state} = Jido.AgentServer.state(pid)
      refute Map.has_key?(state.agent.state, :transformed_by)
      assert state.agent.state[:value] == 75
    end
  end

  describe "transform_result/3 with multiple skills" do
    test "transforms are chained across skills", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: ChainedTransformAgent, jido: jido)

      signal = Signal.new!("value.set", %{value: 25}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state[:value] == 25
      # Both transforms should have run
      assert agent.state[:transformed_by] ==
               JidoTest.AgentServer.SkillTransformTest.MetadataTransformSkill

      assert agent.state[:transformed_at] != nil
    end
  end

  describe "transform_result/3 with cast (no transform)" do
    test "cast path does not apply transforms (fire and forget)", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: MetadataTransformAgent, jido: jido)

      signal = Signal.new!("value.set", %{value: 33}, source: "/test")
      :ok = Jido.AgentServer.cast(pid, signal)

      WaitHelpers.wait_until(
        fn ->
          case Jido.AgentServer.state(pid) do
            {:ok, state} -> state.agent.state[:value] == 33
            _ -> false
          end
        end,
        label: "cast to update state value"
      )

      {:ok, state} = Jido.AgentServer.state(pid)
      assert state.agent.state[:value] == 33
      # No transform applied because it was cast, not call
      refute Map.has_key?(state.agent.state, :transformed_by)
    end
  end
end
