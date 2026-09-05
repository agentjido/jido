defmodule Jido.Examples.Topology.Accounts do
  @moduledoc "Stable group members from explicit account records, suitable for a database query result."
  use Jido.Topology, name: "accounts"

  topology do
    schema Zoi.object(%{
             accounts:
               Zoi.list(
                 Zoi.object(%{
                   account_id: Zoi.string(),
                   label: Zoi.string()
                 })
               )
           })
  end

  agents do
    group :accounts, Jido.Examples.Topology.Cell do
      members input(:accounts)
      key_by :account_id
      initial_state %{label: member(:label)}
    end
  end
end
