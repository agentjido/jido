defmodule Jido.BehaviorTree.DSLTest do
  use Covenant.Case, component: "jido.plugin.behavior_tree", async: true

  alias Jido.BehaviorTree.{Blackboard, Skill, Tick, Tree}
  alias Jido.BehaviorTree.Nodes.Named

  defmodule ExternalAction do
    use Jido.Action, name: "tree_external_action"

    @impl true
    def run(%{result: result}, _context), do: {:ok, %{observed: result}}
  end

  defmodule Trees do
    use Jido.BehaviorTree.DSL

    alias Jido.Joi

    tree :reservation do
      selector :choose do
        sequence :reserve do
          condition :in_stock, blackboard(:available) and blackboard("quantity") >= 2
          wait :hold, milliseconds: 0

          action :record,
                 units <- blackboard("quantity") + 1,
                 inline: [schema: Joi.object(%{units: Joi.integer()}), context: context] do
            {:ok, %{total: total(units, context)}}
          end
        end

        action :unavailable, ExternalAction, params: %{result: [blackboard(:requested) * 2]}
      end
    end

    tree :readiness do
      sequence :ready do
        condition :enabled, blackboard(:enabled)

        action :check, [] do
          {:ok, %{ready: true}}
        end
      end
    end

    defp total(units, %{extra: extra}), do: units + extra
  end

  @tag obligation: "jido.plugin.behavior_tree.I5"
  test "inline code keeps private helpers and context, and sees blackboard changes after a wait" do
    tree = Trees.reservation()
    assert %Named{node_path: [:reservation, :choose]} = tree.root
    blackboard = Blackboard.new(%{:available => true, "quantity" => 2})
    tick = Tick.new_with_context(blackboard, nil, [], %{extra: 2})

    assert {:running, running, tick} = Tree.tick_with_context(tree, tick)
    assert {:success, _, done} = Tree.tick_with_context(running, Tick.put(tick, "quantity", 4))
    assert Tick.get(done, :last_result) == %{total: 7}

    target =
      Jido.Action.Inline.target!(
        Trees,
        host: Jido.BehaviorTree.DSL,
        tree: :reservation,
        node: :choose,
        node: :reserve,
        node: :record,
        role: :action
      )

    assert {:ok, %{total: 7}} = Jido.Exec.run(target, %{units: 5}, %{extra: 2})
  end

  @tag obligation: "jido.plugin.behavior_tree.I5"
  test "false conditions reach the fallback and expression errors stop the tick" do
    tree = Trees.reservation()
    tick = Tick.new(Blackboard.new(%{available: false, requested: 3}))

    assert {:success, _, done} = Tree.tick_with_context(tree, tick)
    assert Tick.get(done, :last_result) == %{observed: [6]}

    assert {{:error, error}, _, _} = Tree.tick_with_context(tree, Tick.new())
    assert Exception.message(error) =~ "Missing blackboard key :available"
  end

  @tag obligation: "jido.plugin.behavior_tree.I5"
  test "the tool wrapper uses a DSL tree and emits named node paths" do
    tree = Trees.readiness()
    skill = Skill.new("readiness", tree)
    handler_id = {__MODULE__, self()}
    event = [:jido, :bt, :node, :tick, :stop]
    :ok = :telemetry.attach(handler_id, event, &__MODULE__.forward_event/4, self())
    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:ok, %{enabled: true, last_result: %{ready: true}}} = Skill.run(skill, %{enabled: true}, %{})
    assert_received {^event, %{node_path: [:readiness, :ready, :check], status: :success}}
  end

  @tag obligation: "jido.plugin.behavior_tree.I5"
  test "an Agent cannot register the Behavior Tree Plugin twice" do
    for {options, second_block} <- [
          {", plugins: [Jido.Plugin.BehaviorTree]", ""},
          {"", "behavior_tree :second do\n  wait :hold, milliseconds: 0\nend"}
        ] do
      source = """
      defmodule Jido.BehaviorTree.DuplicateDSLTestFixture do
        use Jido.Agent, name: "duplicate_behavior_tree"#{options}
        use Jido.BehaviorTree.DSL

        behavior_tree :first do
          wait :hold, milliseconds: 0
        end

        #{second_block}
      end
      """

      assert_raise Spark.Error.DslError, ~r/Duplicate declaration/, fn ->
        Code.compile_string(source, "duplicate_behavior_tree.ex")
      end
    end
  end

  def forward_event(event, _measurements, metadata, pid), do: send(pid, {event, metadata})

  @tag obligation: "jido.plugin.behavior_tree.I5"
  test "rejects unsupported calls in expressions at compile time" do
    source = """
    defmodule Jido.BehaviorTree.InvalidDSLTestFixture do
      use Jido.BehaviorTree.DSL
      tree :invalid do
        condition :invalid, System.system_time()
      end
    end
    """

    assert_raise CompileError, ~r/invalid expression/, fn ->
      Code.compile_string(source, "invalid_behavior_tree.ex")
    end
  end
end
