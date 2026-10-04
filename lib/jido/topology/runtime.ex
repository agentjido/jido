defmodule Jido.Topology.Runtime do
  @moduledoc """
  Owns a topology director, Controller, members, resources, and child runtimes.

  `:eager` starts the complete member target. `:deferred` and `:lazy` start
  control processes only. Calls activate the requested dependency closure.
  Bus publication activates the Bus and delivers to active subscribers only.
  Child commands and exported events pass through explicit gates. Static
  `include` continues to compose one Controller target.

  Use this child after the Jido instance in a `:rest_for_one` application tree.
  Member and director recovery use the configured Jido persistence adapter.
  Each child has an independent restart limit and a scoped logical identity.
  """
  use Supervisor
  alias Jido.Agent.Authoring
  alias Jido.Topology.{Child, Controller, Reference, Validation}
  alias Jido.Topology.Runtime.{Gateway, Gate, Owner}

  @doc "Returns a runtime child specification scoped by instance ID."
  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.fetch!(opts, :id)},
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :transient,
      shutdown: :infinity
    }
  end

  @doc "Validates the complete target before starting its supervision tree."
  def start_link(opts), do: start_link(opts, nil)

  @doc false
  def start_link(opts, parent_gate) do
    with {:ok, opts} <- Authoring.attrs(opts),
         :ok <-
           Authoring.keys(opts, [
             :jido,
             :id,
             :topology,
             :input,
             :director,
             :activation,
             :repair,
             :max_restarts,
             :max_seconds,
             :max_depth
           ]),
         {:ok, id} <- Validation.key(opts[:id]),
         jido when is_atom(jido) and not is_nil(jido) <- opts[:jido],
         {:ok, source, owner, _} <- Child.source(opts[:topology], []),
         {:ok, definition} <- Jido.Topology.new(source),
         {:ok, director} <- Child.director(Map.get(opts, :director, owner)),
         {:ok, activation} <- Child.activation(Map.get(opts, :activation, :eager)),
         :ok <- Child.limits(Map.get(opts, :max_restarts, 3), Map.get(opts, :max_seconds, 5)),
         :ok <- Child.validate_director(director, id),
         :ok <- running(jido),
         :ok <- depth(definition, Map.get(opts, :max_depth, 32)),
         :ok <- repair(Map.get(opts, :repair, :automatic)),
         {:ok, instance} <-
           Jido.Topology.instantiate(definition, id: id, input: Map.get(opts, :input, %{})) do
      config =
        Map.merge(opts, %{
          id: id,
          jido: jido,
          instance: instance,
          director: director,
          parent_gate: parent_gate,
          checkpoint_scope: if(parent_gate, do: parent_gate.checkpoint_scope, else: id),
          activation: activation,
          repair: Map.get(opts, :repair, :automatic)
        })

      with :ok <- available(jido, id),
           :ok <- Owner.await_previous(jido, id),
           do:
             Supervisor.start_link(__MODULE__, config, name: Controller.name(jido, id, :runtime))
    else
      {:error, _} = error -> error
      _ -> Authoring.error("Runtime requires a Jido instance and topology definition")
    end
  end

  defp running(jido) do
    if Process.whereis(Jido.registry_name(jido)),
      do: :ok,
      else: Authoring.error("Jido instance is not running")
  end

  defp available(jido, id) do
    case whereis_runtime(jido, id) do
      nil -> :ok
      pid -> {:error, {:already_started, pid}}
    end
  end

  defp depth(definition, limit) when is_integer(limit) and limit >= 0 and limit <= 32 do
    if Child.depth(definition) <= limit,
      do: :ok,
      else: Authoring.error("Child topology depth exceeds runtime limit")
  end

  defp depth(_, _), do: Authoring.error("Runtime max_depth must be between 0 and 32")
  defp repair(value) when value in [:automatic, :manual], do: :ok
  defp repair(_), do: Authoring.error("Runtime repair must be :automatic or :manual")

  @impl true
  def init(config) do
    {:ok, watcher} = Owner.start(config, self())
    config = Map.put(config, :owner, watcher)

    owner =
      if config.director do
        [
          %{
            id: :director,
            start: {__MODULE__, :start_director, [config, watcher]},
            type: :worker,
            restart: :transient,
            significant: true,
            shutdown: 5_000
          }
        ]
      else
        []
      end

    controller = %{
      id: Controller,
      start: {__MODULE__, :start_controller, [config, watcher]},
      type: :supervisor,
      restart: :transient,
      significant: true,
      shutdown: :infinity
    }

    children =
      owner ++
        [
          controller,
          {Task.Supervisor, name: Controller.name(config.jido, config.id, :runtime_tasks)},
          {Gateway, config}
        ] ++ Enum.map(config.instance.definition.children, &{Gate, {config, &1}})

    Supervisor.init(children, strategy: :rest_for_one, auto_shutdown: :any_significant)
  end

  @doc false
  def start_director(config, checkpoint_owner) do
    with {:ok, pid} <-
           Jido.AgentServer.start_link(
             agent: config.director,
             id: config.id <> "/director",
             jido: config.jido,
             restore_definition: :current,
             checkpoint_owner: checkpoint_owner
           ),
         :ok <- Jido.AgentServer.await_ready(pid) do
      Owner.track(config.owner, pid)
      {:ok, pid}
    end
  end

  @doc false
  def start_controller(config, checkpoint_owner) do
    director = director(config.jido, config.id)

    with :ok <- owner_ready(director) do
      result =
        Controller.start_link(
          [
            jido: config.jido,
            topology: config.instance,
            lifecycle: director,
            checkpoint_owner: checkpoint_owner,
            activation: config.activation,
            repair: config.repair,
            max_restarts: Map.get(config, :max_restarts, 3),
            max_seconds: Map.get(config, :max_seconds, 5)
          ],
          config.parent_gate
        )

      case result do
        {:ok, pid} ->
          Owner.track(config.owner, pid)
          Owner.track(config.owner, lookup(config.jido, config.id, :owner))
          {:ok, pid}

        error ->
          error
      end
    end
  end

  defp owner_ready(nil), do: :ok
  defp owner_ready(pid), do: Jido.AgentServer.await_ready(pid)

  @doc "Calls one member or a declared child command with a bounded deadline."
  def call(jido, id, target, signal, opts \\ [])

  def call(jido, id, {:child, key}, %Jido.Signal{} = signal, opts),
    do: Gate.call(jido, id, key, signal, opts)

  def call(jido, id, target, %Jido.Signal{} = signal, opts),
    do: Gateway.request(jido, id, {:call, target, signal}, opts)

  def call(_jido, _id, _target, _signal, _opts),
    do: Authoring.error("Runtime call requires a Signal")

  @doc "Activates one member, a resource, or all members."
  def activate(jido, id, target \\ :all) do
    with_controller(jido, id, &Controller.activate(&1, target))
  end

  @doc "Returns the currently accepted topology target."
  def target(jido, id), do: with_controller(jido, id, &Controller.target/1)

  @doc "Adds one neutral Agent definition to the current topology target."
  def add_agent(jido, id, key, definition, opts \\ []) do
    with_controller(jido, id, &Controller.add_agent(&1, key, definition, opts))
  end

  @doc "Publishes to an owned Bus. Dormant subscribers remain dormant."
  def publish(jido, id, bus, signals, opts \\ []),
    do: Gateway.request(jido, id, {:publish, bus, signals}, opts)

  @doc "Returns readiness, active and dormant member counts, and child states."
  def status(jido, id) do
    with_controller(jido, id, fn controller ->
      status = Controller.status(controller)
      config = GenServer.call(Controller.name(jido, id, :gateway), :config)

      children =
        Map.new(config.instance.definition.children, fn child ->
          {child.key, Gate.status(jido, id, child.key)}
        end)

      ready? =
        status.status == :ready and
          Enum.all?(children, fn {_, child} -> child.status in [:dormant, :ready] end)

      Map.merge(status, %{ready?: ready?, children: children})
    end)
  end

  @doc "Waits for all activated members and checks child readiness."
  def await_ready(jido, id, timeout \\ 60_000) do
    with {:ok, timeout} <- Gateway.timeout(timeout: timeout) do
      deadline = Gateway.deadline(timeout)

      Gateway.safely(fn ->
        with_controller(jido, id, fn controller ->
          with :ok <- Controller.await_active(controller, Gateway.remaining(deadline)),
               do: await_children(jido, id, deadline)
        end)
      end)
    end
  end

  defp await_children(jido, id, deadline) do
    config =
      GenServer.call(Controller.name(jido, id, :gateway), :config, Gateway.remaining(deadline))

    children =
      Map.new(config.instance.definition.children, fn child ->
        {child.key, Gate.status(jido, id, child.key, Gateway.remaining(deadline))}
      end)

    with :ok <- Gateway.check(deadline),
         do: Gate.await_children(jido, id, children, Gateway.remaining(deadline))
  end

  @doc "Waits until the child gate has completed its current forwarding work."
  def await_gate_idle(jido, id, child, timeout \\ 5_000),
    do: Gate.await_idle(jido, id, child, timeout)

  @doc "Finds a running topology supervisor."
  def whereis_runtime(jido, id), do: lookup(jido, id, :runtime)
  @doc "Finds a child runtime. Returns nil for a dormant or unknown child."
  def whereis_child(jido, id, child), do: Gate.whereis_child(jido, id, child)
  @doc "Finds the Controller."
  def controller(jido, id), do: Controller.whereis(jido, id)
  @doc "Finds the optional director."
  def director(jido, id) do
    if Process.whereis(Jido.registry_name(jido)), do: Jido.whereis_agent(jido, id <> "/director")
  end

  @doc "Finds a live member, including a keyed group member."
  def whereis_member(jido, id, target) do
    lookup_member(controller(jido, id), target)
  end

  defp lookup_member(nil, _), do: nil

  defp lookup_member(pid, {:group, group, member}),
    do: Controller.whereis_agent(pid, group, member)

  defp lookup_member(pid, target), do: Controller.whereis_agent(pid, target)
  @doc "Finds a live Bus."
  def whereis_bus(jido, id, target) do
    case controller(jido, id) do
      nil -> nil
      controller -> Controller.whereis_bus(controller, target)
    end
  end

  @doc false
  def lookup(jido, id, role) do
    if Process.whereis(Jido.registry_name(jido)),
      do: GenServer.whereis(Controller.name(jido, id, role))
  end

  defp with_controller(jido, id, fun) do
    case controller(jido, id) do
      nil -> {:error, :topology_not_running}
      pid -> fun.(pid)
    end
  end

  @doc false
  def child_options(config, child) do
    {:ok, input} = Reference.resolve(child.input, config.instance.input)

    [
      jido: config.jido,
      id: Child.id(config.id, child.key),
      topology: child.topology,
      director: child.director,
      input: input,
      activation: child.activation,
      repair: config.repair,
      max_depth: Map.get(config, :max_depth, 32) - 1
    ]
  end
end
