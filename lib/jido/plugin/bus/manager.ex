defmodule Jido.Plugin.Bus.Manager do
  @moduledoc """
  Starts and owns one `Jido.Signal.Bus` for an Agent.

  The Bus uses the Agent ID as its name by default. Set `:name` when callers
  need another stable name. The Agent's Jido instance is the default Bus scope;
  set `jido: nil` for a global Bus.

      plugins: [
        {Jido.Plugin.Bus.Manager, name: :orders}
      ]

  The Bus stops with its Agent. The default memory store does not survive a Bus
  or Agent restart. Configure a persistent `Jido.Signal.Bus.Store` when records
  and durable subscription cursors must survive that lifecycle.

  When one Agent owns and consumes the same Bus, declare `Manager` before
  `Jido.Plugin.Bus.Client` so the Bus exists before the Client starts.
  """

  use Jido.Plugin

  alias Jido.Plugin.Init
  alias Jido.Signal.Bus

  @doc false
  def child_spec(%Init{} = init) do
    init.options
    |> Keyword.put_new(:name, init.agent_id)
    |> put_default_scope(init.jido)
    |> Bus.child_spec()
    |> Map.put(:id, __MODULE__)
  end

  defp put_default_scope(opts, jido) do
    if Keyword.has_key?(opts, :jido), do: opts, else: Keyword.put(opts, :jido, jido)
  end
end
