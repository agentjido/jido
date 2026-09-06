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

  `:repair` defaults to `:automatic`, which repeats reconciliation using the
  topology's `startup.retry_interval`. Use `repair: :manual` when an application
  owns repair timing. Initial startup still runs once; later passes require
  `reconcile/2`. Both modes use the same bounded local activation and cleanup.
  Manual mode retains child supervision and Plugin runtime recovery. It does
  not change the topology target or provide ownership transfer or cluster policy.
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
         :ok <- Authoring.keys(opts, [:jido, :topology, :repair]),
         repair = Map.get(opts, :repair, :automatic),
         :ok <- validate_repair(repair),
         %Instance{} = instance <- Map.get(opts, :topology),
         {:ok, instance} <-
           Topology.instantiate(instance.definition, id: instance.id, input: instance.input),
         jido when is_atom(jido) and not is_nil(jido) <- Map.get(opts, :jido) do
      Supervisor.start_link(__MODULE__, {jido, instance, repair},
        name: name(jido, instance.id, :controller)
      )
    else
      {:error, _} = error -> error
      _ -> Authoring.error("Controller requires a Jido instance and a topology instance")
    end
  end

  @impl true
  def init({jido, instance, repair}) do
    children = [
      {Task.Supervisor, name: name(jido, instance.id, :tasks)},
      {DynamicSupervisor, name: name(jido, instance.id, :resources), strategy: :one_for_one},
      {Topology.Controller.Runtime, {jido, instance, repair}}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  @doc "Returns status from the latest repair pass."
  def status(controller, timeout \\ 5_000),
    do: GenServer.call(runtime(controller), :status, timeout)

  @doc "Waits for all resources, Agents, and ownership bindings to be ready."
  def await_ready(controller, timeout \\ 60_000),
    do: GenServer.call(runtime(controller), {:await_ready, timeout}, timeout)

  @doc """
  Requests a repair pass against the existing topology target.

  Returns `:ok` after accepting the request. Use `await_ready/2` to wait for
  readiness and `status/2` to inspect errors. Requests during an active pass
  coalesce into one follow-up pass; they do not overlap activation tasks.
  Unchanged live Agents retain their PIDs and state. This is not a target update.
  """
  def reconcile(controller, timeout \\ 5_000),
    do: GenServer.call(runtime(controller), :reconcile, timeout)

  @doc "Resolves a singleton Agent or one keyed group member."
  def whereis_agent(controller, key, member \\ nil),
    do: GenServer.call(runtime(controller), {:agent, key, member})

  @doc "Resolves a topology Bus."
  def whereis_bus(controller, key),
    do: GenServer.call(runtime(controller), {:bus, key})

  defp validate_repair(repair) when repair in [:automatic, :manual], do: :ok

  defp validate_repair(_repair),
    do: Authoring.error("Controller repair must be :automatic or :manual")

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
