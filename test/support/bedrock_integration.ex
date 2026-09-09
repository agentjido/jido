defmodule JidoTest.BedrockIntegration do
  @moduledoc false

  alias Bedrock.ObjectStorage
  alias Bedrock.ObjectStorage.LocalFilesystem
  alias JidoTest.Eventually

  defmodule TestCluster do
    @moduledoc false
    use Bedrock.Cluster, otp_app: :bedrock, name: "jido_v3_persistence_integration"
  end

  defmodule TestRepo do
    @moduledoc false
    use Bedrock.Repo, cluster: TestCluster
  end

  def start!(tmp_dir, on_exit) when is_binary(tmp_dir) and is_function(on_exit, 1) do
    started_node? = ensure_local_node_started!()
    original_config = Application.get_env(:bedrock, TestCluster)
    Application.put_env(:bedrock, TestCluster, node_config(tmp_dir))

    start_supervisor!()

    on_exit.(fn ->
      stop_supervisor()
      restore_config(original_config)
      if started_node?, do: stop_local_node()
    end)

    wait_for_layout!()
    :ok
  end

  def restart! do
    stop_supervisor()
    start_supervisor!()
    wait_for_layout!()
    :ok
  end

  defp node_config(tmp_dir) do
    object_storage =
      ObjectStorage.backend(
        LocalFilesystem,
        root: Path.join([tmp_dir, "coordinator", "object_storage"])
      )

    [
      capabilities: [:coordination, :log, :materializer],
      path_to_descriptor: Path.join(tmp_dir, "bedrock.cluster"),
      object_storage: object_storage,
      coordinator: [path: Path.join(tmp_dir, "coordinator"), persistent: true],
      worker: [path: Path.join(tmp_dir, "workers")],
      durability_mode: :relaxed,
      durability: [desired_replication_factor: 1, desired_logs: 1]
    ]
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

  defp start_supervisor! do
    {:ok, _supervisor} =
      Supervisor.start_link(
        [TestCluster.child_spec([])],
        strategy: :one_for_one,
        name: TestCluster.otp_name(:supervisor)
      )

    :ok
  end

  defp stop_supervisor do
    case Process.whereis(TestCluster.otp_name(:supervisor)) do
      supervisor when is_pid(supervisor) -> Supervisor.stop(supervisor, :normal, 30_000)
      nil -> :ok
    end

    :ok
  catch
    :exit, _reason -> :ok
  end

  defp restore_config(nil), do: Application.delete_env(:bedrock, TestCluster)
  defp restore_config(config), do: Application.put_env(:bedrock, TestCluster, config)

  defp wait_for_layout! do
    Eventually.eventually(
      fn ->
        try do
          TestRepo.transact(
            fn ->
              _value = TestRepo.get("jido-v3-integration/readiness")
              :ok
            end,
            retry_limit: 0,
            timeout_in_ms: 1_000
          ) == :ok
        rescue
          _error -> false
        catch
          _kind, _reason -> false
        end
      end,
      timeout: 30_000,
      interval: 50
    )
  end
end
