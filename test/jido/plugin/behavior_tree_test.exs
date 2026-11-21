defmodule Jido.Plugin.BehaviorTreeTest do
  use Covenant.Case, component: "jido.plugin.behavior_tree", async: true

  alias Jido.BehaviorTree.{Blackboard, Tick, Tree}
  alias Jido.BehaviorTree.Nodes.{Action, Sequence, SetBlackboard, Wait}
  alias Jido.BehaviorTree.Test.Nodes.{ErrorNode, FailureNode}
  alias Jido.Plugin.BehaviorTree
  alias Jido.Plugin.BehaviorTree.StateUpdate
  alias Jido.{Joi, Signal}

  defmodule Add do
    use Jido.Action,
      name: "bt_add",
      schema: Joi.object(%{amount: Joi.integer()})

    @impl true
    def run(%{amount: amount}, %{agent_state: %{total: total}}) do
      {:ok, %{total: total + amount}, [Jido.Agent.Directive.emit("bt.added", %{amount: amount})]}
    end
  end

  defmodule InspectTotal do
    use Jido.Action, name: "bt_inspect_total"

    @impl true
    def run(_, %{agent_state: %{total: total}}) do
      {:ok, Jido.Action.Output.raw(total), [Jido.Agent.Directive.emit("bt.inspected", %{total: total})]}
    end
  end

  defmodule UnguardedAction do
    use Jido.Action, name: "bt_unguarded_action"

    @impl true
    def run(_, _context), do: {:ok, %{behavior_tree: nil}}
  end

  defmodule NonportableNode do
    @behaviour Jido.BehaviorTree.Node
    defstruct []

    @impl true
    def tick(node, _tick), do: {:success, node}

    @impl true
    def tick_with_context(node, tick), do: {:success, node, Tick.put(tick, :temporary, self())}

    @impl true
    def halt(node), do: node
  end

  defmodule TestAgent do
    use Jido.Agent,
      name: "behavior_tree_test_agent",
      plugins: [
        {BehaviorTree,
         %{
           tree:
             Tree.new(
               Sequence.new([
                 SetBlackboard.new(:started, true),
                 Wait.new(0),
                 Action.new(Add, %{amount: {:from_blackboard, :amount}}),
                 Action.new(InspectTotal)
               ])
             ),
           blackboard: %{amount: 2}
         }}
      ]

    state do
      schema Joi.object(%{total: Joi.integer() |> Joi.default(0), unrelated: Joi.string() |> Joi.default("kept")})
    end

    routes do
      signal_source "/bt/test/agent"
    end
  end

  @tag obligation: "jido.plugin.behavior_tree.I1"
  test "contributes routes only when enabled and validates configuration" do
    agent = Jido.Agent.define!(%{name: "without_tree"}) |> Jido.Agent.instantiate!(id: "without-tree")
    assert {:error, %{code: :unmatched_input}} = Jido.Agent.cmd(agent, signal("tick"))
    assert agent.state == %{}

    assert {:error, _} = Jido.Agent.define(%{name: "missing_tree", plugins: [plugin(%{})]})
    assert {:error, _} = define_tree(Tree.new(%URI{}))
    assert {:error, _} = define_tree(Tree.new(Wait.new(0)), reset_on_completion: "yes")
    assert {:error, _} = define_tree(Tree.new(Wait.new(0)), blackboard: %{pid: self()})
    assert {:error, _} = define_tree(Tree.new(Wait.new(0)), unsupported: true)
  end

  @tag obligation: "jido.plugin.behavior_tree.I1"
  test "rejects malformed nested nodes during Agent definition" do
    invalid = Tree.new(Sequence.new([Wait.new(0), :not_a_node]))
    assert {:error, %Jido.Error.ValidationError{path: path}} = define_tree(invalid)
    assert Enum.take(path, -4) == [:tree, :root, :children, 1]
  end

  @tag obligation: "jido.plugin.behavior_tree.I2"
  test "a blackboard write does not retain the previous Agent state" do
    tree = Tree.new(SetBlackboard.new(:ready, true))
    assert {:ok, definition} = define_tree(tree)
    agent = Jido.Agent.instantiate!(definition, id: "bt-bounded-state")

    Enum.reduce(1..8, agent, fn count, current ->
      assert {:ok, next, _} = Jido.Agent.cmd(current, signal("tick"))
      assert %{tree: ^tree, tick_count: ^count, blackboard: blackboard} = next.state.behavior_tree
      assert Blackboard.get(blackboard, :ready)
      next
    end)
  end

  @tag obligation: "jido.plugin.behavior_tree.I2"
  test "resumes the running child, applies result maps in order, and returns Directives" do
    agent = TestAgent.instantiate!(id: "bt-continue")
    assert agent.state.behavior_tree.status == :idle

    assert {:ok, running, [%StateUpdate{}]} = TestAgent.cmd(agent, signal("tick"))
    assert %{status: :running, tick_count: 1, tree: %{root: %{current_index: 1}}} = running.state.behavior_tree
    assert running.state.total == 0

    assert {:ok, changed, _} = TestAgent.cmd(running, signal("blackboard.put", %{key: :started, value: false}))
    assert {:ok, done, [%StateUpdate{}, first, second]} = TestAgent.cmd(changed, signal("tick"))
    assert %{status: :success, tick_count: 2} = done.state.behavior_tree
    assert %{total: 2, unrelated: "kept"} = done.state
    assert Blackboard.get(done.state.behavior_tree.blackboard, :started) == false
    assert %Jido.Action.Output{kind: :raw, value: 2} = Blackboard.get(done.state.behavior_tree.blackboard, :last_result)
    assert %Jido.Agent.Directive.Emit{signal: %{type: "bt.added", data: %{amount: 2}}} = first
    assert %Jido.Agent.Directive.Emit{signal: %{type: "bt.inspected", data: %{total: 2}}} = second
  end

  @tag obligation: "jido.plugin.behavior_tree.I3"
  test "halts without wiping the blackboard and resets to the configured tree and blackboard" do
    agent = TestAgent.instantiate!(id: "bt-reset")
    assert {:ok, running, _} = TestAgent.cmd(agent, signal("tick"))
    assert {:ok, changed, _} = TestAgent.cmd(running, signal("blackboard.merge", %{data: %{extra: true, amount: 9}}))
    assert {:ok, halted, _} = TestAgent.cmd(changed, signal("halt"))

    initial = agent.state.behavior_tree
    assert %{status: :idle, tick_count: 1, tree: tree, blackboard: blackboard} = halted.state.behavior_tree
    assert tree == initial.tree
    assert Blackboard.to_map(blackboard) == %{started: true, extra: true, amount: 9}

    assert {:ok, running, _} = TestAgent.cmd(halted, signal("tick"))
    assert running.state.behavior_tree.status == :running
    assert {:ok, reset, _} = TestAgent.cmd(running, signal("reset"))
    assert reset.state.behavior_tree == initial
    assert {:ok, next, _} = TestAgent.cmd(reset, signal("tick"))
    assert next.state.behavior_tree.status == :running
  end

  @tag obligation: "jido.plugin.behavior_tree.I3"
  test "optional cleanup halts the tree after terminal status without clearing the blackboard" do
    tree = Tree.new(Sequence.new([SetBlackboard.new(:finished, true), FailureNode.new()]))
    assert {:ok, definition} = define_tree(tree, reset_on_completion: true)
    agent = Jido.Agent.instantiate!(definition, id: "bt-completion")
    assert {:ok, done, _} = Jido.Agent.cmd(agent, signal("tick"))
    assert %{status: :failure, tick_count: 1, tree: ^tree} = done.state.behavior_tree
    assert Blackboard.get(done.state.behavior_tree.blackboard, :finished)
  end

  @tag obligation: "jido.plugin.behavior_tree.I4"
  test "rejects bad command input, nonportable node state, and writes to Plugin-owned state" do
    agent = TestAgent.instantiate!(id: "bt-invalid")
    assert {:error, %Jido.Error.ValidationError{}} = TestAgent.cmd(agent, signal("blackboard.put", %{key: :missing}))
    assert {:error, %Jido.Error.ValidationError{}} = TestAgent.cmd(agent, signal("tick", %{extra: true}))

    for node <- [%NonportableNode{}, Action.new(UnguardedAction)] do
      assert {:ok, definition} = define_tree(Tree.new(node))
      agent = Jido.Agent.instantiate!(definition, id: "bt-invalid-#{inspect(node.__struct__)}")
      assert {:error, _} = Jido.Agent.cmd(agent, signal("tick"))
    end
  end

  @tag obligation: "jido.plugin.behavior_tree.I4"
  test "aborts a failed tick and dispatches no earlier Action Directive" do
    tree = Tree.new(Sequence.new([Action.new(Add, %{amount: 5}), ErrorNode.new("node failed")]))

    definition =
      Jido.Agent.define!(%{
        name: "bt_failure",
        signal_source: "/bt/test/agent",
        schema: Joi.object(%{total: Joi.integer() |> Joi.default(0)}),
        plugins: [plugin(%{tree: tree})]
      })

    agent = Jido.Agent.instantiate!(definition, id: "bt-failed")
    assert {:ok, _instance} = Jido.start(name: __MODULE__.Instance)

    {:ok, server} = Jido.start_agent(__MODULE__.Instance, agent, default_dispatch: {:pid, target: self()})
    before = Jido.AgentServer.snapshot(server)

    assert {:ok, %{status: :failed, error: reason}} = Jido.AgentServer.call(server, signal("tick"))
    assert Exception.message(reason) =~ "node failed"
    assert Jido.AgentServer.snapshot(server) == before
    refute_received {:signal, _}
    assert :ok = Jido.stop(__MODULE__.Instance)
  end

  defp define_tree(tree, opts \\ []) do
    data = Map.new([tree: tree] ++ opts)
    Jido.Agent.define(%{name: "configured_tree", plugins: [plugin(data)]})
  end

  defp plugin(data), do: %{id: BehaviorTree.id(), vsn: BehaviorTree.vsn(), provider: BehaviorTree, data: data}

  defp signal(command, data \\ %{}), do: Signal.new!("jido.bt." <> command, data, source: "/bt/test")
end
