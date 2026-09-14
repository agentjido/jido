Code.require_file("../../support/case.exs", __DIR__)

defmodule JidoTest.System.Services.MinIOSnapshots do
  use JidoTest.System.Case, async: false
  @moduletag :service
  @moduletag adapter: :bedrock_minio
  alias Bedrock.ControlPlane.Coordinator
  alias Bedrock.DataPlane.Materializer.Olivine.Logic
  alias Bedrock.ObjectStorage
  alias Jido.AgentServer, as: Server
  alias JidoTest.BedrockIntegration
  alias JidoTest.RecoverableDeliveryAgent, as: Probe
  alias JidoTest.RecoverableDeliverySink, as: Sink
  alias JidoTest.System.Observability

  @tag :research
  @tag skip: "Bedrock snapshot upload and recovery fixes pending: agentjido/jido#370"
  test "real shard snapshots restore Agent state after cluster and materializer rebuild", c do
    level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: level) end)
    server = start_agent(c)
    assert {:ok, _} = Probe.record_and_deliver(server, "snapshot", 17)
    completed(c, server, %{"snapshot" => 17})
    snapshot = Server.snapshot(server)
    stop_agent(c, server)
    assert {:ok, saved, 2} = load(c, snapshot.agent.id)
    assert saved == snapshot.agent
    {_, opts} = c.store
    repo = Keyword.fetch!(opts, :repo)
    cluster = repo.__cluster__()
    backend = Keyword.fetch!(cluster.node_config(), :object_storage)
    {:ok, directory} = Coordinator.fetch_service_directory(cluster.otp_name(:coordinator))

    materializers =
      for {_, {:materializer, {name, local_node}}} <- directory,
          local_node == node(),
          do: Process.whereis(name)

    assert materializers != [] and Enum.all?(materializers, &is_pid/1)

    owner = self()

    paths =
      for pid <- materializers do
        state =
          :sys.replace_state(
            pid,
            fn state ->
              # Drive the real durable-window and snapshot code in its owning
              # process. A zero lag avoids a five-second timer as the test barrier.
              original_lag = state.index_manager.window_lag_time_μs
              ready = %{state | index_manager: %{state.index_manager | window_lag_time_μs: 0}}
              {:ok, ready} = Logic.advance_window(ready)

              result =
                try do
                  Logic.upload_snapshot_before_spindown(ready)
                rescue
                  error -> {:error, error.__struct__}
                end

              send(owner, {:native_snapshot_result, self(), result})

              if result != :ok do
                # Control only: Bedrock passes an iolist to ExAws, which treats
                # non-binary request data as JSON. Upload the same real compacted
                # files as binary so recovery can be checked separately. The final
                # assertion still fails the native upload contract.
                {data, index} = ready.database

                bundle = [
                  File.read!(to_string(data.file_name) <> ".spindown"),
                  File.read!(to_string(index.file_name) <> ".spindown")
                ]

                version =
                  Bedrock.DataPlane.Materializer.Olivine.Database.durable_version(ready.database)
                  |> Bedrock.DataPlane.Version.to_integer()

                :ok =
                  ObjectStorage.Snapshot.write(
                    ready.snapshot,
                    version,
                    IO.iodata_to_binary(bundle)
                  )
              end

              %{ready | index_manager: %{ready.index_manager | window_lag_time_μs: original_lag}}
            end,
            30_000
          )

        state.path
      end

    keys = ObjectStorage.list(backend, "") |> Enum.to_list()
    snapshots = Enum.filter(keys, &String.starts_with?(&1, "s/"))
    assert length(snapshots) >= length(materializers)
    native = native_results(materializers)

    Observability.measure(c.observer, %{
      uploaded_shard_snapshots: length(snapshots),
      native_snapshot_failures: Enum.count(native, &(&1 != :ok))
    })

    recovery =
      try do
        BedrockIntegration.rebuild_materializers!(cluster, repo, paths)
      rescue
        error -> {:error, Exception.message(error)}
      catch
        :exit, reason -> {:error, inspect(reason)}
      end

    assert recovery == :ok,
           "SYSTEM-BEDROCK-05: cluster rebuild did not restore a ready transaction system: #{inspect(recovery)}. Native upload results: #{inspect(native)}. Recent logs:\n#{Observability.format_logs(c.observer)}"

    assert {:ok, ^saved, 2} = load(c, saved.id)
    restored = start_agent(c, id: saved.id, restore: :required)
    assert Server.snapshot(restored) == snapshot
    stop_agent(c, restored)
    assert_empty_agent_pool(c)
    assert Sink.records(c.jido) == %{"snapshot" => 17}
    assert length(Sink.attempts(c.jido)) == 1

    Observability.await_log(c.observer, fn event ->
      event
      |> :logger_formatter.format(%{})
      |> IO.iodata_to_binary()
      |> String.contains?("loaded snapshot from ObjectStorage")
    end)

    Observability.measure(c.observer, %{
      uploaded_shard_snapshots: length(snapshots),
      rebuilt_materializers: length(materializers)
    })

    for result <- native do
      assert result == :ok,
             "SYSTEM-BEDROCK-03: native S3 snapshot upload failed with #{inspect(result)}. Binary-normalized upload and rebuild are a separate control, not a repair."
    end
  end

  defp native_results(pids) do
    for pid <- pids do
      receive do
        {:native_snapshot_result, ^pid, result} -> result
      after
        0 -> :missing_result
      end
    end
  end
end
