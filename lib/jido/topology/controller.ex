defmodule Jido.Topology.Controller do
  @moduledoc """
  Starts and repairs one static topology on one local Jido instance.

  Add this child after the Jido instance in the application supervision tree.
  Use `:rest_for_one` at that application boundary so a Jido restart also
  rebuilds the controller. Agents stay under the existing Jido Agent pool as temporary children.
  The controller owns reactivation and reapplies topology configuration after
  loading saved state.
  Buses and startup tasks have their own supervised children.

  The spike supports eager activation, bounded startup, normal Bus input,
  logical ownership, and periodic repair. It has no live definition updates,
  cluster placement, database adapter, or durable work distribution. A normal
  controller shutdown stops its Agents. Persistent state uses the Jido
  instance's configured adapter and the existing restore contract.
  """
  use Supervisor

  alias Jido.Agent.Authoring
  alias Jido.Topology
  alias Jido.Topology.Instance

  @doc "Returns a child specification scoped by topology instance ID."
  def child_spec(opts) do
    instance = Keyword.fetch!(opts, :topology)

    %{
      id: {__MODULE__, instance.id},
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      shutdown: :infinity
    }
  end

  @doc "Starts a local controller. Returns before the topology is ready."
  def start_link(opts) do
    with {:ok, opts} <- Authoring.attrs(opts),
         :ok <- Authoring.keys(opts, [:jido, :topology]),
         %Instance{} = instance <- Map.get(opts, :topology),
         {:ok, instance} <-
           Topology.instantiate(instance.definition, id: instance.id, input: instance.input),
         jido when is_atom(jido) and not is_nil(jido) <- Map.get(opts, :jido) do
      Supervisor.start_link(__MODULE__, {jido, instance},
        name: name(jido, instance.id, :controller)
      )
    else
      {:error, _} = error -> error
      _ -> Authoring.error("Controller requires a Jido instance and a topology instance")
    end
  end

  @impl true
  def init({jido, instance}) do
    children = [
      {Task.Supervisor, name: name(jido, instance.id, :tasks)},
      {DynamicSupervisor, name: name(jido, instance.id, :resources), strategy: :one_for_one},
      {Topology.Controller.Runtime, {jido, instance}}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  @doc "Returns status from the latest repair pass."
  def status(controller, timeout \\ 5_000),
    do: GenServer.call(runtime(controller), :status, timeout)

  @doc "Waits for all resources, Agents, and ownership bindings to be ready."
  def await_ready(controller, timeout \\ 60_000),
    do: GenServer.call(runtime(controller), {:await_ready, timeout}, timeout)

  @doc "Resolves a singleton Agent or one keyed group member."
  def whereis_agent(controller, key, member \\ nil),
    do: GenServer.call(runtime(controller), {:agent, key, member})

  @doc "Resolves a topology Bus."
  def whereis_bus(controller, key),
    do: GenServer.call(runtime(controller), {:bus, key})

  @doc false
  def name(jido, id, role),
    do: {:via, Registry, {Jido.registry_name(jido), {:topology, id, role}}}

  defp runtime(controller) do
    controller
    |> Supervisor.which_children()
    |> Enum.find_value(fn
      {Topology.Controller.Runtime, pid, _, _} -> pid
      _ -> nil
    end)
  end
end
