defmodule Jido.Persistence.SnapshotTest do
  use Covenant.Case, component: "jido.persistence", async: true
  alias Jido.Agent
  alias Jido.Agent.Directive, as: D
  alias Jido.Persistence
  alias JidoTest.AgentEvolutionFixtures, as: F

  defmodule ContextUpgrade do
    use Jido.Action, name: "persistence_context_upgrade"

    def run(%{snapshot: snapshot}, %{observer: observer, mode: :ok}) do
      send(observer, :upgrade_context)
      {:ok, %{snapshot: snapshot}, []}
    end

    def run(%{snapshot: _snapshot}, %{mode: :error}), do: {:error, :upgrade_rejected}
  end

  defmodule RuntimeSupport do
    def marker, do: :runtime_support
  end

  defmodule RuntimePlugin do
    use Jido.Plugin

    def state_spec(_opts), do: {:runtime_owned, Zoi.integer() |> Zoi.default(0)}
    def runtime_support, do: Jido.Persistence.SnapshotTest.RuntimeSupport
  end

  defmodule InputCheck do
    def valid(_value, _opts), do: :ok
  end

  defmodule OutputCheck do
    def valid(_value, _opts), do: :ok
  end

  defmodule SchemaAction do
    use Jido.Action,
      name: "persistence_schema_action",
      schema:
        Zoi.object(%{
          input: Zoi.any() |> Zoi.refine({Jido.Persistence.SnapshotTest.InputCheck, :valid, []})
        }),
      output_schema:
        Zoi.object(%{
          output: Zoi.any() |> Zoi.refine({Jido.Persistence.SnapshotTest.OutputCheck, :valid, []})
        })

    def run(input, _context), do: {:ok, %{output: input.input}}
  end

  @tag obligation: "jido.persistence.I6"
  test "complete mutated definition and state round trip without a source module" do
    assert {:ok, agent, _} =
             Agent.mutate(F.agent(), [
               D.route_add("extra"),
               D.agent_add(:worker, F.Worker),
               D.plugin_add(F.Counter)
             ])

    assert {:ok, snapshot} = Persistence.snapshot(agent)
    assert snapshot.format == 1
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

  @tag obligation: "jido.persistence.I6"
  test "saved fields are authoritative even if source provenance is unavailable" do
    agent = %{F.agent() | module: NotLoadedSnapshotOrigin, vsn: 7}
    assert {:ok, snapshot} = Persistence.snapshot(agent)
    assert {:ok, ^agent} = Persistence.restore(snapshot)
  end

  @tag obligation: "jido.persistence.I6"
  test "a stale source schema does not replace saved schema or routes" do
    agent = %{F.agent() | module: F.Worker, name: "changed", vsn: 9}
    assert {:ok, snapshot} = Persistence.snapshot(agent)
    assert {:ok, ^agent} = Persistence.restore(snapshot)
    refute agent.routes == F.Worker.definition().routes
  end

  @tag obligation: "jido.persistence.I7"
  test "changed and unavailable code return reference errors" do
    assert {:ok, snapshot} = Persistence.snapshot(F.agent())
    changed = put_in(snapshot.references[F.Work], <<0::128>>)

    assert {:error,
            %Jido.Agent.Error{
              code: :changed_reference,
              path: [0, :references],
              details: %{module: F.Work}
            }} = Persistence.restore(changed)

    missing = %{
      snapshot
      | references: Map.put(snapshot.references, MissingSnapshotCode, <<0::128>>)
    }

    assert {:error,
            %Jido.Agent.Error{
              code: :unavailable_reference,
              path: path,
              details: %{module: MissingSnapshotCode}
            }} = Persistence.restore(missing)

    assert List.last(path) == :references
  end

  @tag obligation: "jido.persistence.I6"
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

    invalid_references = %{snapshot | references: %{"not-an-atom" => <<0::128>>}}

    assert {:error, %Jido.Agent.Error{code: :invalid_snapshot}} =
             Jido.Persistence.Snapshot.envelope(invalid_references)
  end

  @tag obligation: "jido.persistence.I7"
  test "Plugin runtime and Action schemas retain all executable references" do
    plugin_agent =
      Agent.define!(%{
        name: "runtime_reference_snapshot",
        extensions: [
          %{
            id: RuntimePlugin.id(),
            provider: RuntimePlugin,
            vsn: RuntimePlugin.vsn(),
            data: %{}
          }
        ]
      })
      |> Agent.instantiate!(id: "runtime-reference")

    assert {:ok, plugin_snapshot} = Persistence.snapshot(plugin_agent)

    assert plugin_snapshot.references == %{
             RuntimePlugin => RuntimePlugin.module_info(:md5),
             RuntimeSupport => RuntimeSupport.module_info(:md5)
           }

    action_agent =
      Agent.define!(%{
        name: "action_schema_reference_snapshot",
        routes: [%{path: "schema", handler: %{kind: :action, target: SchemaAction}}]
      })
      |> Agent.instantiate!(id: "action-schema-reference")

    assert {:ok, action_snapshot} = Persistence.snapshot(action_agent)

    assert action_snapshot.references == %{
             SchemaAction => SchemaAction.module_info(:md5),
             InputCheck => InputCheck.module_info(:md5),
             OutputCheck => OutputCheck.module_info(:md5)
           }
  end

  @tag obligation: ["jido.persistence.I7", "jido.persistence.I8"]
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

  @tag obligation: "jido.persistence.I8"
  test "upgrade rejects identity changes, invalid state, directives, and invalid results" do
    assert {:ok, snapshot} = Persistence.snapshot(F.agent())

    for mode <- [:state, :nonportable, :raise] do
      assert {:error, _} = Persistence.upgrade(snapshot, F.BadUpgrade, context: %{mode: mode})
    end

    for mode <- [:identity, :origin] do
      assert {:error, %Jido.Agent.Error{code: :upgrade_identity, path: [:agent]}} =
               Persistence.upgrade(snapshot, F.BadUpgrade, context: %{mode: mode})
    end

    for mode <- [:directive, :result, :extra] do
      assert {:error, %Jido.Agent.Error{code: :invalid_upgrade_result}} =
               Persistence.upgrade(snapshot, F.BadUpgrade, context: %{mode: mode})
    end

    assert {:error, %Jido.Agent.Error{code: :invalid_upgrade}} =
             Persistence.upgrade(snapshot, F.Flow)

    assert {:ok, restored} = Persistence.restore(snapshot)
    assert restored === F.agent()
  end

  @tag obligation: "jido.persistence.I8"
  test "upgrade passes context and accepts the exact empty-Directive result" do
    assert {:ok, snapshot} = Persistence.snapshot(F.agent())

    assert {:ok, restored} =
             Persistence.upgrade(snapshot, ContextUpgrade,
               context: %{observer: self(), mode: :ok}
             )

    assert restored === F.agent()
    assert_receive :upgrade_context

    assert {:error,
            %Jido.Action.Error.ExecutionFailureError{details: %{reason: :upgrade_rejected}}} =
             Persistence.upgrade(snapshot, ContextUpgrade, context: %{mode: :error})

    assert {:error, _reason} = Persistence.upgrade(snapshot, String)
  end

  @tag obligation: "jido.persistence.I12"
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

  @tag obligation: "jido.persistence.I7"
  test "a missing reference manifest entry cannot bypass code checks" do
    assert {:ok, snapshot} = Persistence.snapshot(F.agent())

    assert {:error, %{code: :snapshot_references}} =
             Persistence.restore(%{snapshot | references: %{}})

    assert {:error, _} = Persistence.snapshot(Agent.definition(F.agent()))
  end

  @tag obligation: ["jido.persistence.I6", "jido.persistence.I11"]
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

  @tag obligation: "jido.persistence.I7"
  test "Flow snapshots retain their declared executable dependencies" do
    assert {:ok, agent, _} = Agent.mutate(F.agent(), [D.route_replace("run", F.Flow)])
    assert {:ok, snapshot} = Persistence.snapshot(agent)
    assert snapshot.references[F.Flow] == F.Flow.module_info(:md5)
    assert snapshot.references[F.Work] == F.Work.module_info(:md5)
    assert {:ok, ^agent} = Persistence.restore(snapshot)

    assert {:error, %{code: :changed_reference}} =
             Persistence.restore(put_in(snapshot.references[F.Work], <<0::128>>))
  end

  @tag obligation: "jido.persistence.I7"
  test "transform MFA handlers retain their callback module" do
    agent =
      Agent.define!(%{
        name: "transform_snapshot",
        routes: [
          %{
            path: "transform",
            handler: %{kind: :transform, target: {F.Transform, :run, 1}}
          }
        ]
      })
      |> Agent.instantiate!(id: "transform-snapshot")

    assert {:ok, snapshot} = Persistence.snapshot(agent)
    assert snapshot.references == %{F.Transform => F.Transform.module_info(:md5)}
    assert {:ok, ^agent} = Persistence.restore(snapshot)
  end

  @tag obligation: "jido.persistence.I7"
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

  @tag obligation: ["jido.persistence.I6", "jido.persistence.I11"]
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
