defmodule JidoTest.Persistence.Contracts.Agent do
  @moduledoc false

  defmacro __using__(_opts) do
    quote location: :keep do
      alias Jido.AgentServer, as: Server
      alias Jido.Persistence
      alias JidoTest.Persistence.PersistentProbe, as: Probe

      @tag persistence_contract: :agent
      test "Agent creates revision zero and stores every successful Turn", c do
        id = unique_id("agent-contract")
        server = JidoTest.Persistence.Contracts.Agent.start!(c, id)

        assert {:ok, %{state: %{value: 0}}, 0} =
                 Persistence.load_agent_with_revision(c.store, Probe, id, instance: c.jido)

        {:ok, set} = Probe.set_signal(%{value: 7})
        assert {:ok, committed} = Server.call(server, set)
        assert committed.state.value == 7

        {:ok, keep} = Probe.keep_signal(%{})
        assert {:ok, ^committed} = Server.call(server, keep)

        assert {:ok, ^committed, 2} =
                 Persistence.load_agent_with_revision(c.store, Probe, id, instance: c.jido)
      end

      @tag persistence_contract: :agent
      test "hibernate and required restore keep state and revision", c do
        id = unique_id("agent-hibernate")
        server = JidoTest.Persistence.Contracts.Agent.start!(c, id)
        {:ok, signal} = Probe.set_signal(%{value: 11})
        assert {:ok, committed} = Server.call(server, signal)

        monitor = Process.monitor(server)
        assert :ok = Jido.hibernate(c.jido, server)
        assert_receive {:DOWN, ^monitor, :process, ^server, {:shutdown, :hibernate}}, 5_000

        assert {:ok, restored} =
                 Jido.thaw(c.jido, Probe, id, persistence: c.store, restart: :temporary)

        assert Server.snapshot(restored) == %{agent: committed, state_version: 1}
      end

      @tag persistence_contract: :agent
      test "restore policy distinguishes missing records", c do
        required_id = unique_id("agent-required")

        assert {:error, :not_found} =
                 Jido.start_agent(c.jido, Probe,
                   id: required_id,
                   persistence: c.store,
                   restore: :required,
                   restart: :temporary
                 )

        if_found_id = unique_id("agent-if-found")

        assert {:ok, server} =
                 Jido.start_agent(c.jido, Probe,
                   id: if_found_id,
                   persistence: c.store,
                   restore: :if_found,
                   restart: :temporary
                 )

        assert Server.snapshot(server).state_version == 0
      end

      @tag persistence_contract: :agent
      test "a tombstone blocks a delayed writer", c do
        id = unique_id("agent-delete")
        agent = Probe.new!(id: id)

        assert :ok = Persistence.create_agent(c.store, agent, instance: c.jido, revision: 0)
        assert :ok = Persistence.delete_agent(c.store, Probe, id, instance: c.jido)

        assert {:error, :conflict} =
                 Persistence.save_agent(c.store, %{agent | state: %{value: 9}},
                   instance: c.jido,
                   revision: 1,
                   expected_revision: 0
                 )

        assert {:error, :deleted} =
                 Persistence.load_agent(c.store, Probe, id, instance: c.jido)
      end
    end
  end

  def start!(context, id, opts \\ []) do
    defaults = [
      id: id,
      persistence: context.store,
      restore: false,
      restart: :temporary
    ]

    {:ok, server} =
      Jido.start_agent(
        context.jido,
        JidoTest.Persistence.PersistentProbe,
        Keyword.merge(defaults, opts)
      )

    server
  end
end
