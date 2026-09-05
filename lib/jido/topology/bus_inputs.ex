defmodule Jido.Topology.BusInputs do
  @moduledoc false
  use Jido.Plugin

  alias Jido.Plugin.Bus.Client

  def child_spec(init) do
    children =
      init.options
      |> Keyword.fetch!(:subscriptions)
      |> Enum.with_index()
      |> Enum.map(fn {options, index} ->
        Supervisor.child_spec({Client.Runtime, %{init | options: options}}, id: index)
      end)

    %{
      id: __MODULE__,
      start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]},
      type: :supervisor
    }
  end

  @impl true
  def await_ready(supervisor, opts) do
    Enum.reduce_while(Supervisor.which_children(supervisor), :ok, fn
      {_, pid, _, _}, :ok when is_pid(pid) ->
        case Client.await_ready(pid, opts) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end

      _, _ ->
        {:halt, {:error, :subscription_unavailable}}
    end)
  end
end
