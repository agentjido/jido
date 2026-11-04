Code.require_file("../jido_agent_server/support/counter.exs", __DIR__)

defmodule Jido.Persistence.System.RecoveryTest do
  use Jido.Test.Case, async: false

  @moduletag :system
  @moduletag :tmp_dir

  alias Jido.AgentServer, as: Server
  alias Jido.Test.AgentServer.System.Counter

  test "File recovery restores the last committed state and rejects corrupt bytes", c do
    id = unique_id("file-recovery")
    persistence = {Jido.Persistence.File, path: c.tmp_dir}

    {:ok, server} =
      Jido.Test.AgentServer.Assertions.start_agent(c.jido, Counter,
        id: id,
        persistence: persistence,
        persistence_mode: :create
      )

    assert {:ok, saved, []} = Server.call(server, signal("system.runtime.add", %{delta: 7}))
    assert saved.state == %{count: 7}
    assert :ok = Jido.hibernate(c.jido, server)
    assert {:ok, restored} = Jido.thaw(c.jido, Counter, id, persistence: persistence)
    assert :ok = Server.await_ready(restored)
    assert Server.agent(restored) == saved
    assert :ok = Jido.stop_agent(c.jido, restored)

    records = Path.join(c.tmp_dir, "records")
    [record] = File.ls!(records)
    record_path = Path.join(records, record)
    corrupt = <<131, 255, 0, 99>>
    File.write!(record_path, corrupt)

    assert {:error, :invalid_persistence_record} =
             Jido.Test.AgentServer.Assertions.start_result(c.jido, Counter,
               id: id,
               persistence: persistence,
               persistence_mode: :restore
             )

    assert File.read!(record_path) == corrupt
    assert Jido.whereis_agent(c.jido, id) == nil
    assert Jido.agent_count(c.jido) == 0
  end

  test "compare-and-swap rejects a stale concurrent checkpoint", c do
    id = unique_id("file-cas")
    store = {Jido.Persistence.File, path: c.tmp_dir}

    {:ok, server} =
      Jido.Test.AgentServer.Assertions.start_agent(c.jido, Counter,
        id: id,
        persistence: store,
        persistence_mode: :create
      )

    assert {:ok, saved, []} = Server.call(server, signal("system.runtime.add", %{delta: 3}))
    assert :ok = Jido.stop_agent(c.jido, server)

    assert {:ok, ^saved, revision} =
             Jido.Persistence.load_agent_with_revision(store, Counter, id, instance: c.jido)

    first = %{saved | state: %{count: 10}}
    second = %{saved | state: %{count: 20}}

    next_revision = revision + 1

    assert :ok =
             Jido.Persistence.save_agent(store, first,
               revision: next_revision,
               expected_revision: revision,
               instance: c.jido
             )

    assert {:error, :conflict} =
             Jido.Persistence.save_agent(store, second,
               revision: next_revision,
               expected_revision: revision,
               instance: c.jido
             )

    assert {:ok, ^first, ^next_revision} =
             Jido.Persistence.load_agent_with_revision(store, Counter, id, instance: c.jido)
  end
end
