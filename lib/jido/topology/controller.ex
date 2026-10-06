defmodule Jido.Topology.Controller do
  @moduledoc """
  Supervises and connects one topology for one Jido instance.

  Add this child after the Jido instance in the application supervision tree.
  Use `:rest_for_one` at that application boundary so a Jido restart also
  rebuilds this instance. Local Agents use transient OTP children in a local
  supervisor. A coordinator restart preserves healthy Agents and Buses.
  Agent restarts restore committed state and rebuild runtime inputs.

  `:max_restarts` (3) and `:max_seconds` (5) bound local Agent restarts. A
  supporting supervisor failure shuts down the instance. The Controller child
  is transient, so restart-limit shutdown stays stopped. Application policy
  owns any subsequent instance restart. See `guides/topology-supervision.md`.

  `:activation` defaults to `:eager`. `:deferred` and `:lazy` start the
  coordinator without a member pass. `activate/3` selects a target and its
  dependencies. Repair checks only activated targets. A coordinator restart
  retains healthy owned processes. `await_target/3` waits for a single closure.

  The controller supports bounded startup, normal Bus input,
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
      restart: :transient,
      shutdown: :infinity
    }
  end

  @doc "Starts a local controller. Returns before the topology is ready."
  def start_link(opts), do: start_link(opts, nil)

  @doc false
  def start_link(opts, parent_gate) do
    with {:ok, opts} <- Authoring.attrs(opts),
         :ok <-
           Authoring.keys(opts, [
             :jido,
             :topology,
             :repair,
             :lifecycle,
             :activation,
             :checkpoint_owner,
             :max_restarts,
             :max_seconds
           ]),
         max_restarts = Map.get(opts, :max_restarts, 3),
         max_seconds = Map.get(opts, :max_seconds, 5),
         :ok <- validate_restart_limits(max_restarts, max_seconds),
         repair = Map.get(opts, :repair, :automatic),
         :ok <- validate_repair(repair),
         {:ok, activation} <- Jido.Topology.Child.activation(Map.get(opts, :activation, :eager)),
         checkpoint_owner = Map.get(opts, :checkpoint_owner),
         :ok <- validate_checkpoint_owner(checkpoint_owner),
         lifecycle = Map.get(opts, :lifecycle),
         :ok <- validate_lifecycle(lifecycle),
         %Instance{} = instance <- Map.get(opts, :topology),
         {:ok, instance} <-
           Topology.instantiate(instance.definition, id: instance.id, input: instance.input),
         jido when is_atom(jido) and not is_nil(jido) <- Map.get(opts, :jido) do
      Supervisor.start_link(
        __MODULE__,
        {jido, instance, repair, lifecycle, activation, checkpoint_owner, max_restarts,
         max_seconds, parent_gate},
        name: name(jido, instance.id, :controller)
      )
    else
      {:error, _} = error -> error
      _ -> Authoring.error("Controller requires a Jido instance and a topology instance")
    end
  end

  @impl true
  def init(
        {jido, instance, repair, lifecycle, activation, checkpoint_owner, max_restarts,
         max_seconds, parent_gate}
      ) do
    with {:ok, owner} <- Topology.Controller.Owner.start(jido, self(), instance.id) do
      checkpoint_owner = checkpoint_owner || owner

      children = [
        supporting_child(
          {DynamicSupervisor, name: name(jido, instance.id, :resources), strategy: :one_for_one}
        ),
        supporting_child(
          {Topology.Controller.AgentSupervisor,
           name: name(jido, instance.id, :agents),
           max_restarts: max_restarts,
           max_seconds: max_seconds}
        ),
        supporting_child({Task.Supervisor, name: name(jido, instance.id, :tasks)}),
        {Topology.Controller.Runtime,
         {jido, instance, repair, lifecycle, owner, activation, checkpoint_owner, parent_gate}}
      ]

      Supervisor.init(children, strategy: :one_for_one, auto_shutdown: :any_significant)
    else
      {:error, reason} -> exit(reason)
    end
  end

  @doc """
  Returns the latest repair result with current live input readiness.

  The Controller rechecks owned PIDs, required Bus client subscriptions, and
  parent bindings on each public query. A disconnected input makes status
  `:degraded` while its cached Agent and Bus PIDs remain alive.
  """
  def status(controller, timeout \\ 5_000),
    do: GenServer.call(runtime(controller), :status, timeout)

  @doc "Waits for current resources, Agents, Bus inputs, and ownership bindings to be ready."
  def await_ready(controller, timeout \\ 60_000),
    do: GenServer.call(runtime(controller), {:await_ready, timeout}, timeout)

  @doc "Activates a member, a Bus resource, or the complete target and its dependencies."
  def activate(controller, target \\ :all, timeout \\ 5_000),
    do: GenServer.call(runtime(controller), {:activate, target, :ensure}, timeout)

  @doc "Hibernates one accepted Agent member after its admitted work finishes."
  @spec hibernate(Supervisor.supervisor(), term(), keyword()) :: :ok | {:error, term()}
  def hibernate(controller, target, opts \\ []) do
    with {:ok, opts} <- Authoring.attrs(opts),
         :ok <- Authoring.keys(opts, [:timeout]),
         timeout = Map.get(opts, :timeout, 5_000),
         :ok <- validate_lifecycle_timeout(timeout) do
      GenServer.call(
        runtime(controller),
        {:hibernate, target, deadline(timeout)},
        call_timeout(timeout)
      )
    end
  catch
    :exit, {:timeout, _details} -> {:error, {:indeterminate, :hibernate_timeout}}
    :exit, {:noproc, _details} -> {:error, :topology_not_running}
  end

  @doc "Thaws one accepted Agent member and waits for its dependency closure."
  @spec thaw(Supervisor.supervisor(), term(), keyword()) :: :ok | {:error, term()}
  def thaw(controller, target, opts \\ []) do
    with {:ok, opts} <- Authoring.attrs(opts),
         :ok <- Authoring.keys(opts, [:timeout]),
         timeout = Map.get(opts, :timeout, 5_000),
         :ok <- validate_lifecycle_timeout(timeout) do
      GenServer.call(runtime(controller), {:thaw, target, timeout}, call_timeout(timeout))
    end
  catch
    :exit, {:timeout, _details} -> {:error, {:indeterminate, :activation_timeout}}
    :exit, {:noproc, _details} -> {:error, :topology_not_running}
  end

  @doc false
  def checkout_for_call(controller, target, timeout),
    do:
      GenServer.call(
        runtime(controller),
        {:checkout_for_call, target, timeout},
        call_timeout(timeout)
      )

  @doc false
  def release_call(controller, lease) do
    GenServer.call(runtime(controller), {:release_call, lease})
  catch
    :exit, _reason -> :ok
  end

  @doc "Waits for one target and its dependencies, independently of other targets."
  def await_target(controller, target, timeout \\ 60_000),
    do:
      GenServer.call(runtime(controller), {:await_target, target, timeout}, call_timeout(timeout))

  @doc "Waits for the activated target with a structured timeout result."
  def await_active(controller, timeout \\ 60_000),
    do: GenServer.call(runtime(controller), {:await_active, timeout}, call_timeout(timeout))

  defp call_timeout(:infinity), do: :infinity
  defp call_timeout(timeout), do: timeout + 100

  defp deadline(:infinity), do: :infinity
  defp deadline(timeout), do: System.monotonic_time(:millisecond) + timeout

  @doc """
  Requests a repair pass against the existing topology target.

  Returns `:ok` after accepting the request. Use `await_ready/2` to wait for
  readiness and `status/2` to inspect errors. Requests during an active pass
  coalesce into one follow-up pass; they do not overlap activation tasks.
  Unchanged live Agents retain their PIDs and state. This is not a target update.
  """
  def reconcile(controller, timeout \\ 5_000),
    do: GenServer.call(runtime(controller), :reconcile, timeout)

  @doc "Returns the currently accepted topology target."
  @spec target(Supervisor.supervisor(), timeout()) :: Instance.t()
  def target(controller, timeout \\ 5_000),
    do: GenServer.call(runtime(controller), :target, timeout)

  @doc "Adds one neutral Agent definition to the current topology target."
  @spec add_agent(
          Supervisor.supervisor(),
          String.t() | atom(),
          Jido.Agent.definition(),
          keyword()
        ) :: :ok | {:error, term()}
  def add_agent(controller, key, definition, opts \\ [])

  def add_agent(controller, key, %Jido.Agent{} = definition, opts) do
    with {:ok, opts} <- Authoring.attrs(opts),
         :ok <- Authoring.keys(opts, [:initial_state, :depends_on, :node, :timeout]),
         timeout = Map.get(opts, :timeout, 5_000),
         :ok <- validate_timeout(timeout) do
      entry_opts = Map.drop(opts, [:timeout])
      GenServer.call(runtime(controller), {:add_agent, key, definition, entry_opts}, timeout)
    end
  end

  def add_agent(_controller, _key, _definition, _opts),
    do: Authoring.error("Topology member requires a neutral Agent definition")

  @doc "Removes one root Agent definition from an idle topology target."
  @spec remove_agent(Supervisor.supervisor(), String.t() | atom(), keyword()) ::
          :ok | {:error, term()}
  def remove_agent(controller, target, opts \\ []) do
    with {:ok, opts} <- Authoring.attrs(opts),
         :ok <- Authoring.keys(opts, [:timeout]),
         timeout = Map.get(opts, :timeout, 5_000),
         :ok <- validate_timeout(timeout) do
      GenServer.call(runtime(controller), {:remove_agent, target, timeout}, call_timeout(timeout))
    end
  end

  @doc "Validates or resets one inactive member checkpoint without accepting the member."
  @spec prepare_agent_definition(
          Supervisor.supervisor(),
          String.t() | atom(),
          Jido.Agent.definition(),
          Jido.Agent.definition(),
          :preserve | :reset,
          keyword()
        ) :: :ok | {:error, term()}
  def prepare_agent_definition(controller, key, source, candidate, policy, opts \\ [])

  def prepare_agent_definition(
        controller,
        key,
        %Jido.Agent{} = source,
        %Jido.Agent{} = candidate,
        policy,
        opts
      ) do
    with :ok <- definition_policy(policy),
         {:ok, source} <- Jido.Agent.validate_definition(source),
         {:ok, candidate} <- Jido.Agent.validate_definition(candidate),
         :ok <- definition_modules(source, candidate),
         {:ok, opts} <- Authoring.attrs(opts),
         :ok <- Authoring.keys(opts, [:initial_state, :timeout]),
         timeout = Map.get(opts, :timeout, 5_000),
         :ok <- validate_timeout(timeout) do
      GenServer.call(
        runtime(controller),
        {:prepare_agent_definition, key, source, candidate, policy,
         Map.get(opts, :initial_state, %{})},
        timeout
      )
    end
  end

  def prepare_agent_definition(_controller, _key, _source, _candidate, _policy, _opts),
    do: Authoring.error("Definition preparation requires neutral Agent definitions")

  @doc """
  Applies one validated additive Agent target to a ready local controller.

  Existing Agent specifications and all resources must stay unchanged. New
  Agents start through the normal bounded activation pass. Unchanged Agents
  keep their PIDs and committed state. The new target becomes the source for
  later repair passes.

  Use `remove_agent/3` for one root Agent. Use controller replacement for other
  removals, changed Agent definitions, resource changes, or an update requested
  during an active pass.
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

  defp supporting_child(child),
    do: Supervisor.child_spec(child, restart: :temporary, significant: true)

  defp validate_restart_limits(restarts, seconds)
       when is_integer(restarts) and restarts >= 0 and is_integer(seconds) and seconds > 0,
       do: :ok

  defp validate_restart_limits(_, _),
    do: Authoring.error("Controller requires non-negative max_restarts and positive max_seconds")

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

  defp validate_lifecycle_timeout(:infinity), do: :ok
  defp validate_lifecycle_timeout(timeout) when is_integer(timeout) and timeout >= 0, do: :ok

  defp validate_lifecycle_timeout(_timeout),
    do: Authoring.error("Controller lifecycle timeout must be non-negative or :infinity")

  defp definition_modules(%Jido.Agent{module: module}, %Jido.Agent{module: module}), do: :ok

  defp definition_modules(%Jido.Agent{module: source}, %Jido.Agent{module: candidate}),
    do: {:error, {:agent_module_mismatch, source, candidate}}

  defp definition_policy(policy) when policy in [:preserve, :reset], do: :ok
  defp definition_policy(:migrate), do: {:error, {:unsupported_definition_policy, :migrate}}

  defp definition_policy(policy),
    do:
      Authoring.error("Definition preparation policy must be :preserve or :reset", %{
        policy: policy
      })

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

  defp validate_checkpoint_owner(nil), do: :ok
  defp validate_checkpoint_owner(pid) when is_pid(pid) and node(pid) == node(), do: :ok
  defp validate_checkpoint_owner(_), do: Authoring.error("checkpoint_owner must be a local PID")
end
