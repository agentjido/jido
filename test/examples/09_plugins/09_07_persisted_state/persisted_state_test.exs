defmodule JidoTest.Examples.Plugins.PersistedStateTest do
  use JidoTest.Case, async: true

  @moduletag :example

  alias Jido.Examples.Plugins.PersistedState.Agent, as: ExampleAgent
  alias Jido.Persistence
  alias Jido.Persistence.ETS

  test "a Persistence facet stores only its paired Plugin state in a different form" do
    persistence = persistence()
    agent = ExampleAgent.new!(id: unique_id("persisted-plugin"), state: %{visible: 3, owned: 7})
    clean_record_on_exit(persistence, agent, nil)

    assert :ok = Persistence.save_agent(persistence, agent, revision: 2)
    assert %{checkpoint: %{state: %{visible: 3, owned: "owned:7"}}} = record(persistence, agent)

    assert {:ok, ^agent, 2} =
             Persistence.load_agent_with_revision(persistence, ExampleAgent, agent.id)
  end

  test "a malformed or missing owned value cannot restore an Agent", %{jido: jido} do
    persistence = persistence()
    agent = ExampleAgent.new!(id: unique_id("invalid-plugin"), state: %{visible: 3, owned: 7})
    clean_record_on_exit(persistence, agent, jido)

    assert :ok = Persistence.save_agent(persistence, agent, instance: jido)
    saved = record(persistence, agent, jido)

    replace_record(
      persistence,
      agent,
      put_in(saved, [:checkpoint, :state, :owned], "invalid"),
      jido
    )

    assert {:error, :invalid_owned_value} =
             Persistence.load_agent(persistence, ExampleAgent, agent.id, instance: jido)

    assert {:error, :invalid_owned_value} =
             Jido.start_agent(jido, ExampleAgent,
               id: agent.id,
               persistence: persistence,
               restart: :temporary
             )

    assert Jido.whereis_agent(jido, agent.id) == nil

    replace_record(
      persistence,
      agent,
      update_in(saved, [:checkpoint, :state], &Map.delete(&1, :owned)),
      jido
    )

    assert {:error, {:invalid_persistence_record, :plugin_state}} =
             Persistence.load_agent(persistence, ExampleAgent, agent.id, instance: jido)

    assert {:error, {:invalid_persistence_record, :plugin_state}} =
             Jido.start_agent(jido, ExampleAgent,
               id: agent.id,
               persistence: persistence,
               restart: :temporary
             )

    assert Jido.whereis_agent(jido, agent.id) == nil
  end

  defp persistence do
    {ETS, table: __MODULE__}
  end

  defp record({ETS, opts}, agent, instance \\ nil) do
    assert {:ok, bytes} = ETS.get(record_key(agent, instance), opts)
    :erlang.binary_to_term(bytes, [:safe])
  end

  defp replace_record({ETS, opts}, agent, record, instance) do
    assert :ok = ETS.put(record_key(agent, instance), :erlang.term_to_binary(record), opts)
  end

  defp clean_record_on_exit({ETS, opts}, agent, instance) do
    key = record_key(agent, instance)
    on_exit(fn -> ETS.delete(key, opts) end)
  end

  defp record_key(agent, instance), do: Persistence.agent_key(instance, ExampleAgent, agent.id)
end
