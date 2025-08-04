defmodule Jido.Skills.BehaviorTree do
  @moduledoc """
  A skill that enables agents to be driven by behavior trees.
  
  This skill allows agents to use behavior trees for complex, nested logic patterns.
  The behavior tree is built using the `behavior_tree` library, which provides
  standard nodes like sequence, select, and decorators.
  
  ## Example
  
      tree = BehaviorTree.Node.sequence([
        :check_health,
        BehaviorTree.Node.select([
          :attack_enemy,
          :find_food,
          :wander
        ])
      ])
      
      agent_opts = [
        behavior_tree: [
          tree: tree,
          context: %{health: 100, position: {0, 0}}
        ]
      ]
      
  ## Signal Types
  
  - `jido.bt.tick` - Advances the behavior tree by one step
  - `jido.bt.succeed` - Signals that the current behavior succeeded
  - `jido.bt.fail` - Signals that the current behavior failed
  - `jido.bt.reset` - Resets the behavior tree to its initial state
  - `jido.bt.get_current` - Gets the current behavior value
  """
  
  alias Jido.Signal
  alias Jido.Instruction
  require Logger
  
  @behavior_tree_opts_key :behavior_tree
  @behavior_tree_opts_schema [
    tree: [
      type: :any,
      required: true,
      doc: "The behavior tree structure (built with BehaviorTree.Node)"
    ],
    context: [
      type: :map,
      default: %{},
      doc: "The shared context/blackboard for the behavior tree"
    ],
    auto_tick: [
      type: :boolean,
      default: false,
      doc: "Whether to automatically tick the tree on each signal"
    ],
    verbose: [
      type: :boolean,
      default: false,
      doc: "Whether to enable verbose logging"
    ]
  ]

  use Jido.Skill,
    name: "behavior_tree_skill",
    description: "Enables agents to be driven by behavior trees",
    category: "AI",
    tags: ["behavior_tree", "AI", "decision_making"],
    vsn: "0.1.0",
    opts_key: @behavior_tree_opts_key,
    opts_schema: @behavior_tree_opts_schema,
    signal_patterns: [
      "jido.bt.**"
    ]

  def mount(agent, _opts) do
    {:ok, agent}
  end

  def router(_opts \\ []) do
    [
      {"jido.bt.tick", %Instruction{action: Jido.Actions.BehaviorTree.Tick}},
      {"jido.bt.succeed", %Instruction{action: Jido.Actions.BehaviorTree.Succeed}},
      {"jido.bt.fail", %Instruction{action: Jido.Actions.BehaviorTree.Fail}},
      {"jido.bt.reset", %Instruction{action: Jido.Actions.BehaviorTree.Reset}},
      {"jido.bt.get_current", %Instruction{action: Jido.Actions.BehaviorTree.GetCurrent}}
    ]
  end

  def handle_signal(%Signal{type: "jido.bt.tick"} = signal, skill_opts) do
    tree = Keyword.get(skill_opts, :tree)
    context = Keyword.get(skill_opts, :context, %{})
    verbose = Keyword.get(skill_opts, :verbose, false)

    if verbose do
      Logger.info("BehaviorTree: Ticking tree with context: #{inspect(context)}")
    end

    updated_signal = %{signal | data: %{tree: tree, context: context, verbose: verbose}}
    {:ok, updated_signal}
  end

  def handle_signal(%Signal{type: type} = signal, skill_opts) 
      when type in ["jido.bt.succeed", "jido.bt.fail", "jido.bt.reset", "jido.bt.get_current"] do
    tree = Keyword.get(skill_opts, :tree)
    context = Keyword.get(skill_opts, :context, %{})
    verbose = Keyword.get(skill_opts, :verbose, false)

    updated_signal = %{signal | data: %{tree: tree, context: context, verbose: verbose}}
    {:ok, updated_signal}
  end

  def handle_signal(signal, _skill_opts) do
    {:ok, signal}
  end
end
