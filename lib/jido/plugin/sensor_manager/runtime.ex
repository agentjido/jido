defmodule Jido.Plugin.SensorManager.Runtime do
  @moduledoc false

  use Supervisor

  alias Jido.Plugin.Init
  alias Jido.Plugin.SensorManager.Runtime.Controller

  def start_link(%Init{} = init), do: Supervisor.start_link(__MODULE__, init)

  def await_ready(runtime, timeout),
    do: GenServer.call(controller(runtime), :await_ready, timeout)

  def reconcile(runtime, desired, state_version, timeout) do
    GenServer.call(controller(runtime), {:reconcile, desired, state_version}, timeout)
  end

  @doc false
  def sensors(runtime), do: GenServer.call(controller(runtime), :sensors)

  @impl true
  def init(%Init{} = init) do
    children = [
      {DynamicSupervisor, strategy: :one_for_one},
      {Controller, {init, self()}}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp controller(runtime) do
    case Supervisor.which_children(runtime) do
      [{Controller, pid, :worker, _modules} | _rest] when is_pid(pid) ->
        pid

      children ->
        children
        |> Enum.find_value(fn
          {Controller, pid, :worker, _modules} when is_pid(pid) -> pid
          _child -> nil
        end)
    end
  end
end
