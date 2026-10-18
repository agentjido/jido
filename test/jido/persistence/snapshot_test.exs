defmodule Jido.Persistence.SnapshotTest do
  use ExUnit.Case, async: true
  alias Jido.Agent
  alias Jido.Agent.Directive, as: D
  alias Jido.Persistence
  alias JidoTest.AgentEvolutionFixtures, as: F

  test "complete mutated definition and state round trip without a source module" do
    assert {:ok, agent, _} =
             Agent.mutate(F.agent(), [
               D.route_add("extra"),
               D.agent_add(:worker, F.Worker),
               D.plugin_add(F.Counter)
             ])

    assert {:ok, snapshot} = Persistence.snapshot(agent)
    assert snapshot.state_format == :default
    assert snapshot.agent.state.counter == %{saved: 3}

    assert snapshot.agent.topology.agents |> hd() |> Map.fetch!(:definition) ==
             F.Worker.definition()

    assert {:ok, restored} = Persistence.restore(snapshot)
    assert restored.routes === agent.routes
    assert restored.state === agent.state
    assert restored.extensions === agent.extensions
    assert restored.topology.agents |> hd() |> Map.fetch!(:definition) == F.Worker.definition()
    assert agent.topology.agents |> hd() |> Map.fetch!(:definition) == F.Worker
  end

  test "saved fields are authoritative even if source provenance is unavailable" do
    agent = %{F.agent() | module: NotLoadedSnapshotOrigin, vsn: 7}
    assert {:ok, snapshot} = Persistence.snapshot(agent)
    assert {:ok, ^agent} = Persistence.restore(snapshot)
  end

  test "a stale source schema does not replace saved schema or routes" do
    agent = %{F.agent() | module: F.Worker, name: "changed", vsn: 9}
    assert {:ok, snapshot} = Persistence.snapshot(agent)
    assert {:ok, ^agent} = Persistence.restore(snapshot)
    refute agent.routes == F.Worker.definition().routes
  end

  test "changed and unavailable code return reference errors" do
    assert {:ok, snapshot} = Persistence.snapshot(F.agent())
    changed = put_in(snapshot.references[F.Work], <<0::128>>)
    assert {:error, %{code: :changed_reference}} = Persistence.restore(changed)

    missing = %{
      snapshot
      | references: Map.put(snapshot.references, MissingSnapshotCode, <<0::128>>)
    }

    assert {:error, %{code: :unavailable_reference}} = Persistence.restore(missing)
  end

  test "snapshot envelope and final state are checked" do
    assert {:ok, snapshot} = Persistence.snapshot(F.agent())

    for invalid <- [
          nil,
          %{},
          Map.put(snapshot, :extra, true),
          %{snapshot | format: 99},
          %{snapshot | agent: nil},
          %{snapshot | references: %{bad: 1}},
          put_in(snapshot.agent.state.count, "bad")
        ] do
      assert {:error, _} = Persistence.restore(invalid)
    end

    assert {:error, _} = Persistence.snapshot(%{F.agent() | state: %{count: "bad"}})
  end

  test "upgrade runs before old code resolution and validates only target references" do
    assert {:ok, snapshot} = Persistence.snapshot(F.agent())

    old = %{
      snapshot
      | references: %{MissingOldHandler => <<0::128>>},
        agent: %{
          snapshot.agent
          | routes: [
              %{hd(snapshot.agent.routes) | handler: %{kind: :action, target: MissingOldHandler}}
            ]
        }
    }

    assert {:error, %{code: :unavailable_reference}} = Persistence.restore(old)
    assert {:ok, upgraded} = Persistence.upgrade(old, F.Upgrade)
    assert upgraded.id == snapshot.agent.id
    assert upgraded.routes == []
    assert upgraded.state == %{count: 7}
    assert old.references == %{MissingOldHandler => <<0::128>>}
    assert snapshot.agent == F.agent()
  end

  test "upgrade rejects identity changes, invalid state, directives, and invalid results" do
    assert {:ok, snapshot} = Persistence.snapshot(F.agent())

    for mode <- [:identity, :origin, :state, :directive, :result, :extra, :nonportable, :raise] do
      assert {:error, _} = Persistence.upgrade(snapshot, F.BadUpgrade, context: %{mode: mode})
    end

    assert {:ok, restored} = Persistence.restore(snapshot)
    assert restored === F.agent()
  end

  test "state and changed definition share one storage revision; conflicts retain bytes" do
    store = {Persistence.ETS, table: __MODULE__}
    opts = [namespace: "evolution"]
    agent = %{F.agent() | id: "snapshot-#{System.unique_integer([:positive])}"}
    assert :ok = Persistence.create_agent(store, agent, opts)
    assert {:ok, next, _} = Agent.mutate(agent, [D.route_add("new"), D.plugin_add(F.Counter)])
    assert :ok = Persistence.save_agent(store, next, opts ++ [expected_revision: 0, revision: 1])

    assert {:ok, ^next, 1} =
             Persistence.load_agent_with_revision(store, agent.module, agent.id, opts)

    ref = Agent.Ref.new!(namespace: "evolution", id: agent.id)
    key = Persistence.agent_key(ref)
    assert {:ok, bytes} = Persistence.ETS.get(key, elem(store, 1))

    assert {:error, :conflict} =
             Persistence.save_agent(store, agent, opts ++ [expected_revision: 0, revision: 2])

    assert {:ok, ^next, 1} =
             Persistence.load_agent_with_revision(store, agent.module, agent.id, opts)

    assert {:ok, ^bytes} = Persistence.ETS.get(key, elem(store, 1))
  end

  test "a missing reference manifest entry cannot bypass code checks" do
    assert {:ok, snapshot} = Persistence.snapshot(F.agent())

    assert {:error, %{code: :snapshot_references}} =
             Persistence.restore(%{snapshot | references: %{}})

    assert {:error, _} = Persistence.snapshot(Agent.definition(F.agent()))
  end

  test "custom state conversion cannot replace the accepted definition" do
    original = F.Custom.instantiate!(id: "custom", state: %{count: 4})
    assert {:ok, agent, _} = Agent.mutate(original, [D.route_add("saved")])
    assert {:ok, snapshot} = Persistence.snapshot(agent)
    assert snapshot.state_format == :custom
    assert snapshot.agent.state == %{id: "custom", saved: 4}
    assert snapshot.references[F.Custom] == F.Custom.module_info(:md5)
    assert {:ok, ^agent} = Persistence.restore(snapshot)
    refute agent.routes == F.Custom.definition().routes
    missing = %{snapshot | references: Map.delete(snapshot.references, F.Custom)}

    assert {:error, %{code: :snapshot_references}} =
             Persistence.restore(missing, context: %{observer: self()})

    refute_received :restored
  end

  test "Flow snapshots retain their declared executable dependencies" do
    assert {:ok, agent, _} = Agent.mutate(F.agent(), [D.route_replace("run", F.Flow)])
    assert {:ok, snapshot} = Persistence.snapshot(agent)
    assert snapshot.references[F.Flow] == F.Flow.module_info(:md5)
    assert snapshot.references[F.Work] == F.Work.module_info(:md5)
    assert {:ok, ^agent} = Persistence.restore(snapshot)

    assert {:error, %{code: :changed_reference}} =
             Persistence.restore(put_in(snapshot.references[F.Work], <<0::128>>))
  end

  test "schema refinements are code references and tuple defaults remain data" do
    schema =
      Zoi.object(%{
        value:
          Zoi.any() |> Zoi.refine({F.Checks, :valid, []}) |> Zoi.default({NotAModule, :tuple, []})
      })

    agent = Agent.define!(%{name: "schema", schema: schema}) |> Agent.instantiate!(id: "schema")
    assert {:ok, snapshot} = Persistence.snapshot(agent)
    assert snapshot.references == %{F.Checks => F.Checks.module_info(:md5)}
    assert {:ok, ^agent} = Persistence.restore(snapshot)
    assert {:error, _} = Persistence.snapshot(nil)
  end

  test "a changed source module cannot change saved fields or select new callbacks" do
    module = Module.concat(__MODULE__, "Reloaded#{System.unique_integer([:positive])}")

    Module.create(
      module,
      quote do
        def definition, do: Jido.Agent.define!(%{name: "before", module: __MODULE__})
      end,
      Macro.Env.location(__ENV__)
    )

    on_exit(fn ->
      :code.purge(module)
      :code.delete(module)
    end)

    original = Agent.instantiate!(module, id: "reload")
    assert {:ok, snapshot} = Persistence.snapshot(original)
    refute Map.has_key?(snapshot.references, module)
    :code.purge(module)
    :code.delete(module)

    Module.create(
      module,
      quote do
        def definition,
          do:
            Jido.Agent.define!(%{
              name: "after",
              module: __MODULE__,
              schema: Zoi.object(%{required: Zoi.integer()})
            })

        def checkpoint(_, _), do: raise("new checkpoint must not run")
        def restore(_, _), do: raise("new restore must not run")
      end,
      Macro.Env.location(__ENV__)
    )

    assert {:ok, ^original} = Persistence.restore(snapshot)
  end
end
