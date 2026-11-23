defmodule Jido.Examples.DistributedAgents.NativeTicketRecovery do
  @moduledoc "Route a ticket to its fixed home and recover its saved result by Turn ID."

  alias Jido.Signal

  def instance_options(instance, namespace, table, {home, generation}) do
    [
      name: instance,
      namespace: namespace,
      persistence: {Jido.Persistence.Mnesia, table: table, sync_writes: true},
      cluster: [home: home, generation: generation]
    ]
  end

  def open(instance, address, turn_id) do
    signal =
      Signal.new!("examples.distribution.ticket.open", %{ticket_id: address.id},
        source: "/examples/distribution/native-ticket"
      )

    Jido.call(instance, address, signal, turn_id: turn_id, result_handoff: true)
  end

  @doc "Use only after the old home has stopped and cannot restart under its old configuration."
  def move_after_stop(profile, namespace, old_home, new_home) do
    with :ok <- Jido.change_cluster_home(profile, namespace, old_home, new_home),
         do: Jido.check_cluster_home(profile, namespace, new_home)
  end
end
