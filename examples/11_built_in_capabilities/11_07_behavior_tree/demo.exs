Code.require_file("behavior_tree.ex", __DIR__)

alias Jido.AgentServer
alias Jido.Examples.Applications.BehaviorTree.Agent
alias Jido.Signal

instance = Jido.Examples.Applications.BehaviorTree.Demo
{:ok, _instance} = Jido.start(name: instance)

try do
  {:ok, server} =
    Jido.start_agent(instance, Agent, id: "reservation-demo", default_dispatch: {:pid, target: self()})

  for _tick <- 1..2 do
    {:ok, %{status: :committed}} = AgentServer.call(server, Agent.bt_tick_signal!())
    %{state: %{behavior_tree: tree, reserved: reserved, available_stock: stock}} = AgentServer.snapshot(server).agent
    IO.puts("tick=#{tree.tick_count} status=#{tree.status} reserved=#{reserved} available_stock=#{stock}")
  end

  receive do
    {:signal, %Signal{type: "examples.11.07.stock.reserved", data: %{reserved: 3}}} ->
      IO.puts("signal=examples.11.07.stock.reserved reserved=3")
  after
    2_000 -> raise "Stock reservation Signal did not arrive"
  end
after
  Jido.stop(instance)
end
