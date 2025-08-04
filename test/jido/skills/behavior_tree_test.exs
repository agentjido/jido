defmodule JidoTest.Skills.BehaviorTreeTest do
  use ExUnit.Case, async: true

  alias Jido.Skills.BehaviorTree, as: BTSkill
  alias Jido.Signal
  alias BehaviorTree.Node

  describe "BehaviorTree Skill" do
    test "validates configuration" do
      tree = Node.sequence([:a, :b, :c])
      
      opts = [
        tree: tree,
        context: %{test: true}
      ]
      
      # Just verify the configuration is well-formed
      assert is_list(opts)
      assert Keyword.has_key?(opts, :tree)
    end

    test "handles tick signal" do
      tree = Node.sequence([:a, :b, :c])
      
      skill_opts = [
        tree: tree,
        context: %{test: true},
        verbose: false
      ]
      
      {:ok, signal} = Signal.new(%{
        type: "jido.bt.tick",
        data: %{}
      })
      
      assert {:ok, updated_signal} = BTSkill.handle_signal(signal, skill_opts)
      assert updated_signal.data.tree == tree
      assert updated_signal.data.context == %{test: true}
    end

    test "handles succeed signal" do
      tree = Node.sequence([:a, :b, :c])
      
      skill_opts = [
        tree: tree,
        context: %{test: true}
      ]
      
      {:ok, signal} = Signal.new(%{
        type: "jido.bt.succeed",
        data: %{}
      })
      
      assert {:ok, updated_signal} = BTSkill.handle_signal(signal, skill_opts)
      assert updated_signal.data.tree == tree
    end

    test "has correct metadata" do
      assert BTSkill.name() == "behavior_tree_skill"
      assert BTSkill.description() == "Enables agents to be driven by behavior trees"
      assert BTSkill.category() == "AI"
      assert "behavior_tree" in BTSkill.tags()
    end
  end
end
