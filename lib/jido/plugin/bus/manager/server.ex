defmodule Jido.Plugin.Bus.Manager.Server do
  @moduledoc "Owns one local Signal Bus for the Manager package."
  use Jido.AgentServer.Plugin

  alias Jido.Plugin.Bus.Manager
  alias Jido.Plugin.Init
  alias Jido.Signal.Bus

  def child_spec(%Init{} = init) do
    init.options
    |> Keyword.put_new(:name, init.agent_id)
    |> Keyword.put_new(:jido, init.jido)
    |> Bus.child_spec()
    |> Map.put(:id, Manager)
  end
end
