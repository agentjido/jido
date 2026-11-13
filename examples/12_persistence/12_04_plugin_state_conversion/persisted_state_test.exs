Code.require_file("persisted_state_plugin.ex", __DIR__)
Code.require_file("persisted_state.ex", __DIR__)

defmodule Jido.Examples.Persistence.PluginStateConversionTest do
  use Jido.Test.Case, async: true
  @moduletag :integration

  alias Jido.Examples.Persistence.PluginStateConversion.Agent, as: ExampleAgent
  alias Jido.Persistence
  alias Jido.Persistence.ETS

  test "a Persistence facet stores only its paired Plugin state in a different form", c do
    persistence = persistence()
    %{jido: jido} = restart_jido!(c, persistence)

    agent =
      ExampleAgent.instantiate!(id: unique_id("persisted-plugin"), state: %{visible: 3, owned: 7})

    clean_record_on_exit(persistence, agent, jido)

    assert :ok =
             Persistence.save_agent(persistence, agent,
               instance: jido,
               revision: 2
             )

    assert %{checkpoint: %{agent: %{state: %{visible: 3, owned: "owned:7"}}}} =
             record(persistence, agent, jido)

    assert {:ok, ^agent, 2} =
             Persistence.load_agent_with_revision(persistence, ExampleAgent, agent.id, instance: jido)
  end

  test "a malformed or missing owned value cannot restore an Agent", c do
    persistence = persistence()
    %{jido: jido} = restart_jido!(c, persistence)

    agent =
      ExampleAgent.instantiate!(id: unique_id("invalid-plugin"), state: %{visible: 3, owned: 7})

    clean_record_on_exit(persistence, agent, jido)

    assert :ok = Persistence.save_agent(persistence, agent, instance: jido)
    saved = record(persistence, agent, jido)

    replace_record(
      persistence,
      agent,
      put_in(saved.checkpoint.agent.state.owned, "invalid"),
      jido
    )

    assert {:error, :invalid_owned_value} =
             Persistence.load_agent(persistence, ExampleAgent, agent.id, instance: jido)

    assert_restore_rejected(jido, agent.id)

    replace_record(
      persistence,
      agent,
      update_in(saved.checkpoint.agent.state, &Map.delete(&1, :owned)),
      jido
    )

    assert {:error, {:invalid_persistence_record, :plugin_state}} =
             Persistence.load_agent(persistence, ExampleAgent, agent.id, instance: jido)

    assert_restore_rejected(jido, agent.id)
  end

  defp assert_restore_rejected(jido, id) do
    # Restore can stop the activation before start_agent returns its endpoint.
    case Jido.start_agent(jido, ExampleAgent,
           id: id,
           persistence_mode: :restore
         ) do
      {:ok, server} -> assert {:error, _reason} = Jido.AgentServer.await_ready(server)
      {:error, _reason} -> :ok
    end

    eventually(fn -> Jido.whereis_agent(jido, id) == nil and Jido.resident_agent_count(jido) == 0 end)
  end

  defp persistence do
    {ETS, table: __MODULE__}
  end

  defp record({ETS, opts}, agent, instance) do
    assert {:ok, bytes} = ETS.get(record_key(agent, instance), opts)
    assert {:ok, record} = Jido.Persistence.Codec.Term.decode(bytes, trusted: true)
    record
  end

  defp replace_record({ETS, opts}, agent, record, instance) do
    assert {:ok, bytes} = Jido.Persistence.Codec.Term.encode(record)
    assert :ok = ETS.put(record_key(agent, instance), bytes, opts)
  end

  defp clean_record_on_exit({ETS, opts}, agent, instance) do
    key = record_key(agent, instance)
    on_exit(fn -> ETS.delete(key, opts) end)
  end

  defp record_key(agent, instance),
    do:
      Persistence.agent_key(
        Jido.Agent.Ref.new!(namespace: Jido.Instance.NamespaceRegistry.namespace(instance), id: agent.id)
      )
end
