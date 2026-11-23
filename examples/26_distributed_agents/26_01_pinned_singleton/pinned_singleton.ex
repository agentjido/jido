defmodule Jido.Examples.DistributedAgents.PinnedSingleton do
  @moduledoc "Sends work to the Jido instance that hosts a configured namespace."

  alias Jido.Agent.Address
  alias Jido.Signal

  @doc "Calls the selected owner once. A transport error leaves the Turn outcome unknown."
  def call({owner_node, instance}, %Address{} = address, %Signal{} = signal) do
    reply_timeout = 6_000
    owner_call_timeout = 7_000
    :erpc.call(owner_node, Jido, :call, [instance, address, signal, owner_call_timeout], reply_timeout)
  catch
    :error, {:erpc, reason} when reason in [:noconnection, :timeout] ->
      {:error, {:outcome_unknown, reason}}
  end
end
