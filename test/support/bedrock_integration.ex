defmodule JidoTest.BedrockIntegration do
  @moduledoc false

  alias Bedrock.ObjectStorage
  alias Bedrock.ObjectStorage.LocalFilesystem

  defmodule TestCluster do
    @moduledoc false
    use Bedrock.Cluster, otp_app: :bedrock, name: "jido_v3_persistence_integration"
  end

  defmodule TestRepo do
    @moduledoc false
    use Bedrock.Repo, cluster: TestCluster
  end

  def start!(tmp_dir, on_exit, opts \\ []) when is_binary(tmp_dir) and is_function(on_exit, 1) do
    cluster = Keyword.get(opts, :cluster, TestCluster)
    repo = Keyword.get(opts, :repo, TestRepo)
    started_node? = ensure_local_node_started!()
    original_config = Application.get_env(:bedrock, cluster)
    original_storage = Application.fetch_env(:bedrock, ObjectStorage)

    backend =
      Keyword.get(
        opts,
        :object_storage,
        ObjectStorage.backend(LocalFilesystem,
          root: Path.join([tmp_dir, "coordinator", "object_storage"])
        )
      )

    config = node_config(tmp_dir, backend)
    Application.put_env(:bedrock, cluster, config)
    # Materializer snapshot restore reads this application-level setting, not
    # the cluster setting. Isolate both stores for each test cluster.
    Application.put_env(:bedrock, ObjectStorage, backend: backend)

    on_exit.(fn ->
      try do
        stop_supervisor(cluster)
      after
        restore_config(cluster, original_config)

        case original_storage do
          :error -> Application.delete_env(:bedrock, ObjectStorage)
          {:ok, value} -> Application.put_env(:bedrock, ObjectStorage, value)
        end

        if started_node?, do: stop_local_node()
      end
    end)

    start_ready!(cluster, repo)
    :ok
  end

  def restart!(cluster \\ TestCluster, repo \\ TestRepo) do
    stop_supervisor(cluster)
    start_ready!(cluster, repo)
    :ok
  end

  defp node_config(tmp_dir, object_storage) do
    [
      capabilities: [:coordination, :log, :materializer],
      path_to_descriptor: Path.join(tmp_dir, "bedrock.cluster"),
      object_storage: object_storage,
      coordinator: [path: Path.join(tmp_dir, "coordinator"), persistent: true],
      worker: [path: Path.join(tmp_dir, "workers"), object_storage: object_storage],
      durability_mode: :relaxed,
      durability: [desired_replication_factor: 1, desired_logs: 1]
    ]
  end

  def rebuild_materializers!(cluster, repo, paths) do
    stop_supervisor(cluster)

    root =
      cluster.node_config() |> Keyword.fetch!(:worker) |> Keyword.fetch!(:path) |> Path.expand()

    # Cold materializers require snapshots. Retain the coordinator and log WAL;
    # S3 snapshots do not replace the cluster's log durability contract.
    for path <- paths do
      unless String.starts_with?(Path.expand(path), root <> "/"),
        do: raise("materializer path is outside the owned worker directory")

      :ok = File.rename(path, path <> "-before-rebuild")
    end

    start_ready!(cluster, repo)
  end

  defp ensure_local_node_started! do
    if Node.self() == :nonode@nohost do
      epmd_path = :os.find_executable(~c"epmd")

      if epmd_path == false do
        raise "epmd is not available"
      end

      {_output, 0} =
        System.cmd(List.to_string(epmd_path), ["-daemon"], stderr_to_stdout: true)

      node_name = :"jido_bedrock_#{System.unique_integer([:positive])}"
      {:ok, _pid} = :net_kernel.start([node_name, :shortnames])
      Node.set_cookie(:jido_bedrock_test)
      true
    else
      false
    end
  end

  defp stop_local_node do
    case :net_kernel.stop() do
      :ok -> :ok
      {:error, :not_allowed} -> :ok
    end
  end

  defp start_supervisor!(cluster) do
    {:ok, supervisor} =
      Supervisor.start_link(
        [cluster.child_spec([])],
        strategy: :one_for_one,
        name: cluster.otp_name(:supervisor)
      )

    # The on_exit callback owns shutdown, including the unlinked placeholder.
    # Do not race it with the test process's exit signal.
    Process.unlink(supervisor)
    :ok
  end

  defp stop_supervisor(cluster) do
    # Bedrock's placeholder is outside the cluster supervision tree and can
    # survive its Distributor's normal exit. Own its cleanup explicitly before
    # rebuilding the same cluster identity; this is not a shutdown contract test.
    placeholder_name =
      cluster.otp_name_for_worker(Bedrock.ControlPlane.Distributor.Placeholder.worker_id())

    placeholder = Process.whereis(placeholder_name)
    monitor = if placeholder, do: Process.monitor(placeholder)

    case Process.whereis(cluster.otp_name(:supervisor)) do
      supervisor when is_pid(supervisor) -> Supervisor.stop(supervisor, :normal, 30_000)
      nil -> :ok
    end

    if monitor do
      stop_placeholder(placeholder)

      receive do
        {:DOWN, ^monitor, :process, ^placeholder, _reason} -> :ok
      after
        10_000 ->
          raise ExUnit.AssertionError,
            message: "Bedrock placeholder did not stop: #{inspect(placeholder_name)}"
      end
    end

    :ok
  end

  defp stop_placeholder(pid) do
    GenServer.stop(pid, :shutdown, 10_000)
  catch
    :exit, {:noproc, _} -> :ok
  end

  defp restore_config(cluster, nil), do: Application.delete_env(:bedrock, cluster)
  defp restore_config(cluster, config), do: Application.put_env(:bedrock, cluster, config)

  defp start_ready!(cluster, repo) do
    recover!(cluster, repo, fn -> start_supervisor!(cluster) end)
  end

  def recover!(cluster, repo, trigger) do
    ref = make_ref()
    handler = {__MODULE__, ref}
    owner = self()

    :ok =
      :telemetry.attach_many(
        handler,
        [[:bedrock, :recovery, :started], [:bedrock, :recovery, :layout_persisted]],
        &__MODULE__.observe_layout/4,
        {cluster, owner, ref}
      )

    try do
      trigger.()

      receive do
        {:bedrock_layout, ^ref, director} ->
          # Layout publication precedes Distributor startup. Wait for its
          # startup continuation to publish routing coverage before one real
          # transaction proves readiness. These are message barriers, not polls.
          %{distributor: distributor} = :sys.get_state(director, 30_000)
          :sys.get_state(distributor, 30_000)

          :ok =
            repo.transact(
              fn ->
                repo.get("jido-v3-integration/readiness")
                :ok
              end,
              retry_limit: 0,
              timeout_in_ms: 10_000
            )
      after
        30_000 ->
          raise ExUnit.AssertionError,
            message: "Bedrock did not publish a layout: #{inspect(cluster)}"
      end
    after
      :telemetry.detach(handler)
    end
  end

  def observe_layout(
        [:bedrock, :recovery, :started],
        _measurements,
        metadata,
        {cluster, _owner, ref}
      ) do
    Process.put({__MODULE__, ref}, metadata.cluster == cluster)
  end

  def observe_layout(
        [:bedrock, :recovery, :layout_persisted],
        _measurements,
        _metadata,
        {_cluster, owner, ref}
      ) do
    if Process.delete({__MODULE__, ref}), do: send(owner, {:bedrock_layout, ref, self()})
  end
end
