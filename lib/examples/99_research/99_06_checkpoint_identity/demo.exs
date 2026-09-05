alias Jido.Examples.CheckpointIdentityProbe, as: Probe
alias Jido.Examples.PersistenceProbeStore, as: Store

{:ok, process} = Store.start_link([])
store = {Store, store: process}

try do
  :ok = Probe.store_mismatched_checkpoint(store, "requested-agent", "different-agent")

  case Jido.Persistence.load_agent(store, Probe, "requested-agent") do
    {:ok, agent} ->
      IO.inspect(%{requested_id: "requested-agent", restored_id: agent.id}, label: "GAP")

    {:error, reason} ->
      IO.inspect(reason, label: "Checkpoint rejected")
  end
after
  Elixir.Agent.stop(process)
end
