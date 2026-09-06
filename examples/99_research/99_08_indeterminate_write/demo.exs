# This example prints results for its user.
# credo:disable-for-this-file Credo.Check.Warning.IoInspect

alias Jido.AgentServer, as: Server
alias Jido.Examples.IndeterminateWriteProbe, as: Probe
alias Jido.Examples.PersistenceProbeStore, as: Store

{:ok, process} = Store.start_link([])
jido = Jido.Examples.IndeterminateWriteDemo
{:ok, instance} = Jido.start_link(name: jido)
store = {Store, store: process, write_result: :indeterminate}
context = %{on_execute: fn id -> IO.puts("Action executed: #{id}") end}

try do
  {:ok, agent} = Jido.start_agent(jido, Probe, id: "write-probe", persistence: store)
  IO.inspect(Probe.increment(agent, "first", 1, context: context), label: "First reply")

  {:ok, stored, revision} =
    Jido.Persistence.load_agent_with_revision(store, Probe, "write-probe", instance: jido)

  IO.inspect(%{count: stored.state.count, revision: revision}, label: "Stored state")

  try do
    IO.inspect(Server.snapshot(agent).agent.state, label: "Live state")
    IO.inspect(Probe.increment(agent, "second", 10, context: context), label: "Second reply")
  catch
    :exit, _ -> IO.puts("The Agent stopped accepting work.")
  end
after
  Supervisor.stop(instance)
  Elixir.Agent.stop(process)
end
