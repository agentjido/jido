Code.require_file("../support/case.exs", __DIR__)

defmodule JidoTest.System.Services.BedrockFaults do
  use JidoTest.System.Case, async: false
  @moduletag :service
  @moduletag adapter: :bedrock
  alias Jido.AgentServer, as: Server
  alias JidoTest.BedrockIntegration
  alias JidoTest.RecoverableDeliveryAgent, as: Probe
  alias JidoTest.RecoverableDeliverySink, as: Sink

  setup c do
    server = start_agent(c)
    assert {:ok, _} = Probe.record_and_deliver(server, "saved", 7)
    completed(c, server, %{"saved" => 7})
    snapshot = Server.snapshot(server)
    stop_agent(c, server)
    {_, opts} = c.store
    repo = Keyword.fetch!(opts, :repo)
    {:ok, repo: repo, cluster: repo.__cluster__(), snapshot: snapshot}
  end

  for component <- [:coordinator, :log] do
    @component component
    @tag :research
    test "real #{@component} replacement retains the Agent checkpoint and effect identity", c do
      coordinator = c.cluster.otp_name(:coordinator)
      {:ok, directory} = Bedrock.ControlPlane.Coordinator.fetch_service_directory(coordinator)

      pid =
        if @component == :coordinator do
          Process.whereis(coordinator)
        else
          {name, local_node} =
            Enum.find_value(directory, fn
              {_id, {:log, ref}} -> ref
              _ -> nil
            end)

          assert local_node == node()
          Process.whereis(name)
        end

      assert is_pid(pid)
      monitor = Process.monitor(pid)

      recovered =
        try do
          BedrockIntegration.recover!(c.cluster, c.repo, fn ->
            Process.exit(pid, :kill)
            assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 10_000
          end)
        catch
          :exit, reason -> {:error, reason}
        end

      # If live replacement fails, a fixture-assisted full restart is a control
      # experiment only. It must not turn the live-recovery probe into a pass.
      if recovered != :ok, do: BedrockIntegration.restart!(c.cluster, c.repo)

      assert_checkpoint(c)

      assert recovered == :ok,
             "SYSTEM-BEDROCK-02: #{@component} replacement did not restore a ready transaction system: #{inspect(recovered)}"
    end
  end

  test "three cluster restarts reuse the same identity and retain the same checkpoint", c do
    for _ <- 1..3 do
      assert :ok = BedrockIntegration.restart!(c.cluster, c.repo)
      assert_checkpoint(c)
    end
  end

  @tag :research
  test "Bedrock cluster shutdown must remove its own placeholder", c do
    name = c.cluster.otp_name_for_worker(Bedrock.ControlPlane.Distributor.Placeholder.worker_id())
    placeholder = Process.whereis(name)
    assert is_pid(placeholder)
    monitor = Process.monitor(placeholder)
    root = Process.whereis(c.cluster.otp_name(:supervisor))
    :ok = Supervisor.stop(root, :normal, 30_000)
    retained? = Process.alive?(placeholder)

    # Record the unassisted outcome first. Cleanup must not leave this global
    # worker behind, even while the unsupported shutdown contract fails.
    if retained?, do: GenServer.stop(placeholder, :shutdown, 10_000)
    assert_receive {:DOWN, ^monitor, :process, ^placeholder, _}, 10_000
    assert Process.whereis(name) == nil
    assert Sink.records(c.jido) == %{"saved" => 7}
    assert length(Sink.attempts(c.jido)) == 1

    refute retained?,
           "SYSTEM-BEDROCK-01: the placeholder survived its cluster supervisor. Fixture cleanup removed it; Bedrock shutdown did not."
  end

  defp assert_checkpoint(c) do
    assert {:ok, stored, 2} = load(c, c.snapshot.agent.id)
    assert stored == c.snapshot.agent
    restored = start_agent(c, id: stored.id, restore: :required)
    assert Server.snapshot(restored) == c.snapshot
    stop_agent(c, restored)
    assert_empty_agent_pool(c)
    assert Sink.records(c.jido) == %{"saved" => 7}
    assert length(Sink.attempts(c.jido)) == 1
  end
end
