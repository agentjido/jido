defmodule Jido.Topology.Controller do
  @moduledoc """
  Starts and repairs one topology for one Jido instance.

  Add this child after the Jido instance in the application supervision tree.
  Use `:rest_for_one` at that application boundary so a Jido restart also
  rebuilds the controller. Agents stay under the existing Jido Agent pool as temporary children.
  The controller owns reactivation and reapplies topology configuration after
  loading saved state.
  Buses and startup tasks have their own supervised children.

  The controller supports eager activation, bounded startup, normal Bus input,
  logical ownership, periodic repair, additive Agent updates, and exact Erlang
  node placement. It does not select nodes or rebalance Agents. Those policies
  belong in a control Agent or Plugin. A normal controller shutdown stops its
  Agents.
  Persistent state uses the Jido instance's configured adapter and the existing
  restore contract.

  `:repair` defaults to `:automatic`, which repeats reconciliation using the
  topology's `startup.retry_interval`. Use `repair: :manual` when an application
  owns repair timing. Initial startup still runs once; later passes require
  `reconcile/2`. Both modes use the same bounded activation and cleanup.
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
         :ok <- Authoring.keys(opts, [:jido, :topology, :repair, :lifecycle]),
         repair = Map.get(opts, :repair, :automatic),
         :ok <- validate_repair(repair),
         lifecycle = Map.get(opts, :lifecycle),
         :ok <- validate_lifecycle(lifecycle),
         %Instance{} = instance <- Map.get(opts, :topology),
         {:ok, instance} <-
           Topology.instantiate(instance.definition, id: instance.id, input: instance.input),
         jido when is_atom(jido) and not is_nil(jido) <- Map.get(opts, :jido) do
      Supervisor.start_link(__MODULE__, {jido, instance, repair, lifecycle},
        name: name(jido, instance.id, :controller)
      )
    else
      {:error, _} = error -> error
      _ -> Authoring.error("Controller requires a Jido instance and a topology instance")
    end
  end

  @impl true
  def init({jido, instance, repair, lifecycle}) do
    with {:ok, owner} <- Topology.Controller.Owner.start(jido, self(), instance.id) do
      children = [
        {Task.Supervisor, name: name(jido, instance.id, :tasks)},
        {DynamicSupervisor, name: name(jido, instance.id, :resources), strategy: :one_for_one},
        {Topology.Controller.Runtime, {jido, instance, repair, lifecycle, owner}}
      ]

      Supervisor.init(children, strategy: :one_for_all)
    end
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

  @doc """
  Applies one validated additive Agent target to a ready local controller.

  Existing Agent specifications and all resources must stay unchanged. New
  Agents start through the normal bounded activation pass. Unchanged Agents
  keep their PIDs and committed state. The new target becomes the source for
  later repair passes.

  Use controller replacement for removals, changed Agent definitions, resource
  changes, or an update requested during an active pass.
  """
  @spec update(Supervisor.supervisor(), Instance.t(), timeout()) :: :ok | {:error, term()}
  def update(controller, %Instance{} = target, timeout \\ 5_000) do
    with {:ok, target} <-
           Topology.instantiate(target.definition, id: target.id, input: target.input) do
      GenServer.call(runtime(controller), {:update, target}, timeout)
    end
  end

  @doc """
  Moves one topology Agent to an exact Erlang node.

  This function is a placement mechanism. It does not select a node or apply a
  rebalance policy. Use the `:member` option for one group member. The call
  returns after the old Agent has stopped and the new repair pass has started.
  Use `await_ready/2` to wait for activation on the target node. The Agent
  restores through configured shared persistence. Without shared persistence,
  it starts from its declared initial state.
  """
  @spec place_agent(Supervisor.supervisor(), term(), node(), keyword()) ::
          :ok | {:error, term()}
  def place_agent(controller, target, target_node, opts \\ []) do
    with {:ok, opts} <- Authoring.attrs(opts),
         :ok <- Authoring.keys(opts, [:member, :timeout]),
         timeout = Map.get(opts, :timeout, 5_000),
         :ok <- validate_timeout(timeout) do
      GenServer.call(
        runtime(controller),
        {:place_agent, target, Map.get(opts, :member), target_node, timeout},
        timeout
      )
    end
  end

  @doc "Resolves a singleton Agent or one keyed group member."
  def whereis_agent(controller, key, member \\ nil),
    do: GenServer.call(runtime(controller), {:agent, key, member})

  @doc "Returns the effective Erlang node for a topology Agent."
  def agent_node(controller, key, member \\ nil),
    do: GenServer.call(runtime(controller), {:agent_node, key, member})

  @doc "Resolves a topology Bus."
  def whereis_bus(controller, key),
    do: GenServer.call(runtime(controller), {:bus, key})

  @doc "Finds a local Topology Controller by Jido instance and topology ID."
  @spec whereis(atom(), String.t()) :: pid() | nil
  def whereis(jido, topology_id) when is_atom(jido) and is_binary(topology_id) do
    registry = Jido.registry_name(jido)

    if Process.whereis(registry) do
      case Registry.lookup(registry, {:topology, topology_id, :controller}) do
        [{pid, _value}] -> pid
        [] -> nil
      end
    else
      nil
    end
  end

  defp validate_repair(repair) when repair in [:automatic, :manual], do: :ok

  defp validate_repair(_repair),
    do: Authoring.error("Controller repair must be :automatic or :manual")

  defp validate_lifecycle(nil), do: :ok
  defp validate_lifecycle(pid) when is_pid(pid), do: :ok
  defp validate_lifecycle(%Jido.Agent.Ref{}), do: :ok

  defp validate_lifecycle(_value),
    do: Authoring.error("Controller lifecycle target must be an Agent PID or Ref")

  defp validate_timeout(:infinity), do: :ok
  defp validate_timeout(timeout) when is_integer(timeout) and timeout > 0, do: :ok

  defp validate_timeout(_timeout),
    do: Authoring.error("Controller timeout must be a positive integer or :infinity")

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
