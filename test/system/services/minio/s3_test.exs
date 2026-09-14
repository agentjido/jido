Code.require_file("../../support/case.exs", __DIR__)

defmodule JidoTest.System.Services.S3MinIO do
  use JidoTest.System.Case, async: false
  @moduletag :service
  @moduletag adapter: :s3_minio

  alias Jido.Agent.Ref
  alias Jido.AgentServer, as: Server
  alias Jido.Persistence
  alias JidoTest.RecoverableDeliveryAgent, as: Probe

  use JidoTest.System.Scenarios.Checkpoints
  use JidoTest.System.Scenarios.Effects
  use JidoTest.System.Scenarios.Fencing
  use JidoTest.System.Scenarios.Recovery
  use JidoTest.System.Scenarios.Execution
  use JidoTest.System.Scenarios.Restoration
  use JidoTest.System.Scenarios.Overload
  use JidoTest.System.Scenarios.Topology

  test "real object tombstones repeat and maintenance deletion removes only the selected key",
       c do
    server = start_agent(c)
    id = Server.agent(server).id
    assert {:ok, _agent} = Probe.record_and_deliver(server, "maintenance", 1)
    stop_agent(c, server)

    opts = [instance: c.jido, namespace: c.namespace]
    assert :ok = Persistence.delete_agent(c.store, Probe, id, opts)
    assert :ok = Persistence.delete_agent(c.store, Probe, id, opts)
    assert {:error, :deleted} = load(c, id)

    {adapter, adapter_opts} = c.store
    key = Persistence.agent_key(Ref.new!(namespace: c.namespace, id: id))
    assert {:ok, _tombstone, _token} = adapter.get(key, adapter_opts)
    assert :ok = adapter.delete(key, adapter_opts)
    assert {:error, :not_found} = adapter.get(key, adapter_opts)

    # A token read before maintenance deletion cannot recreate that object.
    probe = "s3-deletion-probe-#{id}"
    assert :ok = adapter.compare_and_swap(probe, :not_found, "before", adapter_opts)
    assert {:ok, "before", token} = adapter.get(probe, adapter_opts)
    assert :ok = adapter.delete(probe, adapter_opts)

    assert {:error, :conflict} =
             adapter.compare_and_swap(probe, {:token, token}, "stale", adapter_opts)

    assert {:error, :not_found} = adapter.get(probe, adapter_opts)
  end
end
