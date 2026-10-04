alias Jido.AgentServer
alias Jido.Examples.Research.DataDefinedTopology, as: Example
alias Jido.Examples.Research.DataDefinedTopology.Topology, as: HybridTopology
alias Jido.Topology.Controller

jido = Jido.Examples.Research.DataDefinedTopology.Instance
{:ok, jido_pid} = Jido.start_link(name: jido)

try do
  # The initial topology comes from topology.ex and uses the existing DSL.
  {:ok, initial} = HybridTopology.new(id: "hybrid-demo")
  {:ok, controller} = Controller.start_link(jido: jido, topology: initial)

  try do
    :ok = Controller.await_ready(controller)
    observer = Controller.whereis_agent(controller, :observer)

    {:ok, committed} =
      Example.record(observer, "examples.research.data_defined_topology.observer.record", 7)

    IO.puts("DSL topology ready. Observer total: #{committed.state.total}.")

    {:ok, alice} = Example.stored_alice()
    IO.puts("Alice decoded from JSON. Adding Alice to the running topology.")

    # This fails on current V3 before the Controller receives the new target.
    {:ok, target} = Example.expanded(initial, alice)
    :ok = Controller.update(controller, target)
    :ok = Controller.await_ready(controller)

    alice_server = Controller.whereis_agent(controller, :alice)
    IO.inspect(AgentServer.agent(alice_server).state, label: "Alice state")
  after
    :ok = Supervisor.stop(controller)
  end
after
  :ok = Supervisor.stop(jido_pid)
end
