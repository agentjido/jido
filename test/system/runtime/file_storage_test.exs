Code.require_file("../support/case.exs", __DIR__)

defmodule JidoTest.System.FileStorageTest do
  use JidoTest.System.Case, async: false
  @moduletag :system
  @moduletag adapter: :file

  alias Jido.AgentServer, as: Server
  alias Jido.Persistence
  alias JidoTest.RecoverableDeliveryAgent, as: Probe
  alias JidoTest.RecoverableDeliverySink, as: Sink
  alias JidoTest.System.Observability

  setup c do
    server = start_agent(c)
    assert {:ok, _} = Server.call(server, Probe.record_and_deliver_signal!("saved", 7))
    completed(c, server, %{"saved" => 7})
    snapshot = Server.snapshot(server)
    {adapter, opts} = c.store
    directory = Path.join(Keyword.fetch!(opts, :path), "records")
    [file] = File.ls!(directory)
    path = Path.join(directory, file)

    key =
      Persistence.agent_key(Jido.Agent.Ref.new!(namespace: c.namespace, id: snapshot.agent.id))

    {:ok,
     server: server,
     snapshot: snapshot,
     path: path,
     directory: directory,
     key: key,
     adapter: adapter,
     opts: opts}
  end

  for restore <- [:required, :if_found] do
    @restore restore
    test "#{@restore} restoration rejects a corrupt file without replacing it", c do
      stop_agent(c, c.server)
      corrupt = <<131, 255, 0, 99>>
      File.write!(c.path, corrupt)

      assert {:error, :invalid_persistence_record} =
               Jido.start_agent(c.jido, Probe,
                 id: c.snapshot.agent.id,
                 persistence: c.store,
                 restore: @restore
               )

      assert File.read!(c.path) == corrupt
      assert Jido.whereis_agent(c.jido, c.snapshot.agent.id) == nil
      assert_empty_agent_pool(c)
      assert_sink_unchanged(c)
      Observability.assert_persistence(c.observer, :error)
    end
  end

  test "a real temporary-file write failure stops the Agent and preserves its checkpoint", c do
    File.chmod!(c.directory, 0o500)

    try do
      monitors = monitor_agent_tree(c, c.server)
      signal = Probe.record_and_deliver_signal!("must-not-run", 99)

      # File returns the OS error without a write-outcome classification.
      # Persistence treats that uncertainty as indeterminate and fences the Agent.
      assert {:error, {:persistence_failed, {:indeterminate, :eacces}}} =
               Server.call(c.server, signal)

      await_down(monitors)
      assert_empty_agent_pool(c)
      assert {:ok, saved, 2} = load(c, c.snapshot.agent.id)
      assert saved == c.snapshot.agent
      assert File.ls!(c.directory) == [Path.basename(c.path)]
      Observability.assert_turn(c.observer, signal, :error, false)
      Observability.assert_persistence(c.observer, :indeterminate)
    after
      File.chmod!(c.directory, 0o700)
    end

    assert_restores(c)
  end

  test "a real rename failure removes its temporary file and retains the prior checkpoint", c do
    stop_agent(c, c.server)
    backup = c.path <> ".backup"
    File.rename!(c.path, backup)
    File.mkdir!(c.path)
    marker = Path.join(c.path, "owned-marker")
    File.write!(marker, "occupied")

    try do
      # put/3 and CAS share the atomic write helper. A directory at the target
      # reaches rename through put; CAS would reject the earlier read instead.
      assert {:error, :eisdir} = c.adapter.put(c.key, "replacement", c.opts)
      assert File.read!(marker) == "occupied"

      assert Enum.sort(File.ls!(c.directory)) ==
               Enum.sort([Path.basename(c.path), Path.basename(backup)])
    after
      File.rm!(marker)
      File.rmdir!(c.path)
      File.rename!(backup, c.path)
    end

    assert_restores(c)
  end

  test "a physical delete failure leaves the complete record available for restoration", c do
    stop_agent(c, c.server)
    bytes = File.read!(c.path)
    File.chmod!(c.directory, 0o500)

    try do
      assert {:error, :eacces} = c.adapter.delete(c.key, c.opts)
      assert File.read!(c.path) == bytes
    after
      File.chmod!(c.directory, 0o700)
    end

    assert_restores(c)
  end

  defp assert_restores(c) do
    restored = start_agent(c, id: c.snapshot.agent.id, restore: :required)
    assert Server.snapshot(restored) == c.snapshot
    stop_agent(c, restored)
    assert_empty_agent_pool(c)
    assert_sink_unchanged(c)
  end

  defp assert_sink_unchanged(c) do
    assert Sink.records(c.jido) == %{"saved" => 7}
    assert length(Sink.attempts(c.jido)) == 1
  end
end
