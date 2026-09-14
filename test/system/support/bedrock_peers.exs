defmodule JidoTest.System.StrictCluster do
  @moduledoc false
  use Bedrock.Cluster, otp_app: :bedrock, name: "jido_system_strict"
end

defmodule JidoTest.System.StrictRepo do
  @moduledoc false
  use Bedrock.Repo, cluster: JidoTest.System.StrictCluster
end

defmodule JidoTest.System.BedrockPeers do
  @moduledoc false
  use GenServer
  alias JidoTest.System.{StrictCluster, StrictRepo}

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)
  def init(_), do: {:ok, %{count: 0, director: nil, waiters: [], logs: []}}

  def prepare(directory, objects, nodes) do
    {:ok, _} = Supervisor.start_child(Jido.Supervisor, __MODULE__)
    :ok = :logger.add_handler(__MODULE__, __MODULE__, %{})
    File.mkdir_p!(directory)
    descriptor = Path.join(directory, "bedrock.cluster")

    :ok =
      Bedrock.Cluster.Descriptor.write_to_file!(
        descriptor,
        Bedrock.Cluster.Descriptor.new(StrictCluster.name(), nodes)
      )

    backend = Bedrock.ObjectStorage.backend(Bedrock.ObjectStorage.LocalFilesystem, root: objects)

    bootstrap =
      Bedrock.ClusterBootstrap.Discovery.create_initial(hd(nodes))
      |> Map.merge(%{
        coordinators: Enum.map(nodes, &%{node: Atom.to_string(&1)}),
        parameters: %{desired_logs: 3, desired_replication_factor: 3}
      })

    case Bedrock.ObjectStorage.put_if_not_exists(
           backend,
           "bootstrap",
           Bedrock.SystemKeys.ClusterBootstrap.to_binary(bootstrap)
         ) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end

    Application.put_env(:bedrock, Bedrock.ObjectStorage, backend: backend)

    Application.put_env(:bedrock, StrictCluster,
      capabilities: [:coordination, :log, :materializer],
      path_to_descriptor: descriptor,
      object_storage: backend,
      coordinator: [path: Path.join(directory, "coordinator"), persistent: true],
      worker: [path: Path.join(directory, "workers"), object_storage: backend],
      durability_mode: :strict,
      durability: [desired_logs: 3, desired_replication_factor: 3]
    )

    :telemetry.attach(
      __MODULE__,
      [:bedrock, :recovery, :layout_persisted],
      &__MODULE__.layout/4,
      nodes
    )
  end

  def boot, do: Supervisor.start_child(Jido.Supervisor, StrictCluster.child_spec([]))

  def log(event, _config), do: GenServer.cast(__MODULE__, {:log, event})
  def logs, do: GenServer.call(__MODULE__, :logs)

  def layout(_event, _measures, _meta, nodes) do
    # This isolated peer runs one Bedrock cluster. Send the layout barrier to
    # all three independent control channels; the host BEAM stays unnamed.
    for peer_node <- nodes, do: GenServer.cast({__MODULE__, peer_node}, {:layout, self()})
  end

  def ready(after_count \\ 0) do
    {count, director} = GenServer.call(__MODULE__, {:after_layout, after_count}, 30_000)
    %{distributor: distributor} = :sys.get_state(director, 10_000)
    :sys.get_state(distributor, 10_000)

    :ok =
      StrictRepo.transact(
        fn ->
          StrictRepo.get("system/readiness")
          :ok
        end,
        retry_limit: 0,
        timeout_in_ms: 10_000
      )

    :ok = Bedrock.Durability.require(StrictCluster, :strict)
    {count, StrictCluster.transaction_system_layout!()}
  end

  def start_jido(namespace, directory) do
    JidoTest.System.PeerRuntime.start(
      namespace,
      directory,
      {Jido.Persistence.Bedrock, repo: StrictRepo, timeout_in_ms: 10_000}
    )
  end

  def log_nodes do
    {:ok, directory} =
      Bedrock.ControlPlane.Coordinator.fetch_service_directory(StrictCluster.coordinator!())

    for {_, {:log, {_, peer_node}}} <- directory, do: peer_node
  end

  def handle_call(:logs, _from, state), do: {:reply, Enum.reverse(state.logs), state}

  def handle_call({:after_layout, count}, from, state) do
    if state.count > count,
      do: {:reply, {state.count, state.director}, state},
      else: {:noreply, %{state | waiters: [{from, count} | state.waiters]}}
  end

  def handle_cast({:log, event}, state),
    do: {:noreply, %{state | logs: Enum.take([event | state.logs], 100)}}

  def handle_cast({:layout, director}, state) do
    count = state.count + 1
    {done, waiting} = Enum.split_with(state.waiters, &(elem(&1, 1) < count))
    for {caller, _} <- done, do: GenServer.reply(caller, {count, director})
    {:noreply, %{state | count: count, director: director, waiters: waiting}}
  end
end
