alias Jido.BehaviorTree.{Agent, Skill, Tree}
alias Jido.BehaviorTree.Nodes.{Sequence, SetBlackboard, Wait}
alias Jido.Joi

tree = Tree.new(Sequence.new([Wait.new(0), SetBlackboard.new(:ready, true)]))
{:ok, executor} = Agent.start_link(tree: tree)

try do
  :running = Agent.tick(executor)
  :success = Agent.tick(executor)
  true = Agent.get(executor, :ready)
  IO.puts("standalone=running,success ready=true")
after
  GenServer.stop(executor)
end

skill = Skill.new("check_readiness", tree, "Checks readiness", output_schema: Joi.object(%{ready: Joi.boolean()}))
%{"name" => "check_readiness"} = Skill.to_tool(skill)
{:ok, %{ready: true}} = Skill.run(skill, %{}, %{})
IO.puts("tool=check_readiness ready=true")
