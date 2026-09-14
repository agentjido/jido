defmodule JidoTest.System.ControlledWork do
  @moduledoc false
  use Jido.Action, name: "system_controlled_work"

  def run(%{value: value} = params, context) do
    if gate = params[:gate] do
      send(params.observer, {:work_held, gate, self()})
      receive do: ({:release_work, ^gate} -> :ok)
    end

    if params[:reject],
      do: {:error, :system_rejected},
      else: {:ok, %{context.agent_state | value: value}}
  end
end

defmodule JidoTest.System.ControlledAgent do
  @moduledoc false
  use Jido.Agent,
    name: "system_controlled_agent",
    schema: Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)}),
    routes: [{"system.work", JidoTest.System.ControlledWork}]

  def signal(value, opts \\ []) do
    Jido.Signal.new!("system.work", Map.put(Map.new(opts), :value, value), source: "/system")
  end
end
