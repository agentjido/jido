alias Jido.Examples.CheckpointPortabilityProbe, as: Probe
alias Jido.Examples.PersistenceProbeStore, as: Store

{:ok, process} = Store.start_link([])
store = {Store, store: process}

try do
  :ok = Probe.store_payload(store, "portable-agent", %{job: %{worker: self()}})

  case Jido.Persistence.load_agent(store, Probe, "portable-agent") do
    {:ok, agent} ->
      IO.inspect(%{accepted_process_handle: is_pid(agent.state.payload.job.worker)}, label: "GAP")

    {:error, reason} ->
      IO.inspect(reason, label: "Checkpoint rejected")
  end
after
  Elixir.Agent.stop(process)
end
