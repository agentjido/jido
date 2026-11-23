defmodule Jido.AgentServer.EctoStateTest do
  use Covenant.Case, component: "jido.agent_server.plugin_runtime", async: false

  alias Ecto.Adapters.SQL
  alias Ecto.Changeset
  alias Jido.{AgentServer, Joi}
  alias Jido.AgentServer.TurnResult
  alias Jido.Plugin.EctoState
  alias Jido.Test.Eventually
  alias Jido.Test.Persistence.{EctoRepo, EctoSupport}

  defmodule LedgerEntry do
    use Ecto.Schema

    @primary_key {:turn_id, :string, autogenerate: false}
    schema "turn_ledger" do
      field(:agent_id, :string)
      field(:count, :integer)
    end
  end

  defmodule Ledger do
    use Jido.Plugin

    @impl true
    def admit(_runtime, admission, _opts) do
      pause_after_read(admission.caller_context)
      {:ok, :ledger_admission}
    end

    @impl true
    def state_spec(_opts), do: {:ledger_count, Joi.integer() |> Joi.nullable() |> Joi.default(nil)}

    @impl true
    def reduce(reduction, _opts) do
      count =
        Enum.find_value(reduction.directives, fn
          %EctoState.Update{attrs: %{count: count}} -> count
          _directive -> nil
        end)

      {:ok, count}
    end

    @impl true
    def after_commit(_runtime, %{plugin_state: nil, runtime_input: nil}, _opts), do: :ok

    def after_commit(_runtime, %{runtime_input: nil} = commit, _opts) do
      entry = %LedgerEntry{turn_id: commit.turn_id, agent_id: commit.agent_id, count: commit.plugin_state}
      with {:ok, _entry} <- EctoRepo.insert(entry), do: :ok
    end

    # Let the conflict test edit the row after admission reads it.
    defp pause_after_read(%{writer: writer}) do
      send(writer, {:row_loaded, self()})

      receive do
        :write_finished -> :ok
      end
    end

    defp pause_after_read(_context), do: :ok
  end

  defmodule CounterState do
    use Ecto.Schema

    @primary_key {:id, :string, autogenerate: false}
    schema "counter_state" do
      field(:count, :integer)
      field(:lock_version, :integer, default: 1)
    end

    def repo, do: EctoRepo

    def changeset(row, attrs) do
      row
      |> Changeset.cast(attrs, [:count])
      |> Changeset.validate_number(:count, greater_than_or_equal_to: 0)
    end
  end

  defmodule Add do
    use Jido.Action, name: "ecto_state_add", schema: Joi.object(%{by: Joi.integer()})

    @impl true
    def run(%{by: by}, context) do
      row = context.plugin_inputs[EctoState].runtime.row
      attrs = %{count: row.count + by}
      {:ok, attrs, [EctoState.update(attrs)]}
    end
  end

  defmodule Counter do
    use Jido.Agent, name: "ecto_state_counter"

    state do
      ecto(CounterState)
    end

    # The optional ledger observes admission after the built-in Plugin reads the row.
    Jido.Agent.DSL.register_plugin!(Ledger, __ENV__)

    routes do
      signal_source "/test/ecto-state"

      route "ecto_state.add", Add, as: :add do
        state(:unchanged)
        reply("ecto_state.added", from: output())
      end

      route "ecto_state.read", as: :read do
        action _params, context: context do
          {:ok, %{count: context.plugin_inputs[EctoState].runtime.row.count}}
        end

        state(:unchanged)
        reply("ecto_state.current", from: output())
      end
    end
  end

  setup do
    path = EctoSupport.database_path(:ecto_state)
    on_exit(fn -> EctoSupport.remove_database(path) end)

    repo_opts = Keyword.put(EctoSupport.repo_start_options(path), :pool_size, 1)
    start_supervised!({EctoRepo, repo_opts})

    SQL.query!(EctoRepo, """
    CREATE TABLE counter_state (
      id TEXT PRIMARY KEY NOT NULL,
      count INTEGER NOT NULL,
      lock_version INTEGER NOT NULL
    )
    """)

    EctoRepo.insert!(%CounterState{id: "counter", count: 10})

    SQL.query!(EctoRepo, """
    CREATE TABLE turn_ledger (
      turn_id TEXT PRIMARY KEY NOT NULL,
      agent_id TEXT NOT NULL,
      count INTEGER NOT NULL
    )
    """)

    config = [name: __MODULE__.Instance, namespace: "test/ecto-state"]
    server = start_counter(config)
    %{server: server, config: config, repo_opts: repo_opts}
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I14"
  test "the built-in Plugin can commit without a ledger Plugin", %{config: config} do
    defmodule StandaloneCounter do
      use Jido.Agent, name: "ecto_state_standalone_counter"

      state do
        ecto(CounterState)
      end

      routes do
        signal_source "/test/ecto-state"

        route "ecto_state.add", Add, as: :add do
          state(:unchanged)
        end
      end
    end

    EctoRepo.insert!(%CounterState{id: "standalone", count: 10})
    assert {:ok, server} = Jido.start_agent(config[:name], StandaloneCounter, id: "standalone")
    assert :ok = AgentServer.await_ready(server)
    assert {:ok, %TurnResult{status: :committed}} = AgentServer.call(server, StandaloneCounter.add_signal!(%{by: 3}))
    assert %CounterState{count: 13, lock_version: 2} = EctoRepo.get!(CounterState, "standalone")
    assert EctoRepo.all(LedgerEntry) == []
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I14"
  test "each Turn reads the canonical row, including after restart", context do
    %{server: server, config: config, repo_opts: repo_opts} = context

    assert EctoRepo.all(LedgerEntry) == []
    assert %TurnResult{durability: :memory} = add_and_check_ledger(server, 2, 12)

    assert %CounterState{count: 12, lock_version: 2} = EctoRepo.get!(CounterState, "counter")
    edit_count(40)

    add_and_check_ledger(server, 2, 42)

    assert %CounterState{count: 42, lock_version: 4} = EctoRepo.get!(CounterState, "counter")

    assert :ok = stop_supervised(config[:name])
    assert :ok = stop_supervised(EctoRepo)
    start_supervised!({EctoRepo, repo_opts})
    server = start_counter(config)

    assert Enum.sort(EctoRepo.all(LedgerEntry) |> Enum.map(& &1.count)) == [12, 42]
    add_and_check_ledger(server, 1, 43)

    assert %CounterState{count: 43, lock_version: 5} = EctoRepo.get!(CounterState, "counter")
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I14"
  test "a stale row fails the Turn and leaves the ledger empty", %{server: server} do
    pending = AgentServer.submit(server, add_signal(2), context: %{writer: self()})
    assert_receive {:row_loaded, admission}, 2_000

    edit_count(40)
    send(admission, :write_finished)

    assert {:ok, %TurnResult{status: :failed, error: :stale_ecto_state, reply: nil}} =
             AgentServer.await(pending)

    assert %CounterState{count: 40, lock_version: 2} = EctoRepo.get!(CounterState, "counter")
    assert EctoRepo.all(LedgerEntry) == []
    assert %{agent: %{state: %{ecto_changes: nil}}} = AgentServer.snapshot(server)
    add_and_check_ledger(server, 2, 42)
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I14"
  @tag :tmp_dir
  test "the Ecto Plugin rejects writes with Jido persistence and allows reads", %{config: config, tmp_dir: path} do
    durable_config =
      Keyword.merge(config,
        name: __MODULE__.DurableInstance,
        namespace: config[:namespace] <> "/durable",
        persistence: {Jido.Persistence.File, path: path}
      )

    server = start_counter(durable_config)

    assert {:ok,
            %TurnResult{status: :failed, durability: :durable, error: :ecto_state_requires_memory_turn, reply: nil}} =
             AgentServer.call(server, add_signal(2))

    assert %CounterState{count: 10, lock_version: 1} = EctoRepo.get!(CounterState, "counter")
    assert %{agent: %{state: %{ecto_changes: nil}}} = AgentServer.snapshot(server)
    assert EctoRepo.all(LedgerEntry) == []

    assert {:ok, %TurnResult{status: :committed, durability: :durable, reply: %{data: %{count: 10}}}} =
             AgentServer.call(server, Counter.read_signal!())
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I15"
  test "snapshot returns the current Ecto fields through agent.state", %{server: server} do
    before_edit = AgentServer.snapshot(server)
    assert %{agent: %{state: %{count: 10, lock_version: 1, ledger_count: nil}}} = before_edit
    edit_count(40)

    handler = {__MODULE__, make_ref()}
    query_event = EctoRepo.config()[:telemetry_prefix] ++ [:query]
    :ok = :telemetry.attach(handler, query_event, &__MODULE__.forward_query/4, self())
    on_exit(fn -> :telemetry.detach(handler) end)

    assert %{agent: %{state: %{count: 40, lock_version: 2, ledger_count: nil}}} =
             snapshot = AgentServer.snapshot(server)

    assert_receive {:sql_query, "SELECT " <> query}
    assert query =~ ~s("counter_state")
    assert snapshot.agent_revision == before_edit.agent_revision
    assert snapshot.persistence_revision == before_edit.persistence_revision
    assert EctoRepo.all(LedgerEntry) == []

    assert {:ok, persisted} = Jido.Persistence.snapshot(snapshot.agent)
    refute Map.has_key?(persisted.agent.state, :count)
    assert {:ok, _agent} = Jido.Persistence.restore(persisted)
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I15"
  test "snapshot reports a missing row or unavailable Repo", %{server: server} do
    EctoRepo.delete!(EctoRepo.get!(CounterState, "counter"))
    assert {:error, :ecto_state_not_found} = AgentServer.snapshot(server)

    assert :ok = stop_supervised(EctoRepo)
    assert {:error, :ecto_state_unavailable} = AgentServer.snapshot(server)
    assert %{agent_revision: 0} = AgentServer.status(server)
  end

  def forward_query(_event, _measurements, metadata, receiver),
    do: send(receiver, {:sql_query, metadata.query})

  @tag obligation: "jido.agent_server.plugin_runtime.I14"
  test "a read-only Turn uses the row and does not advance its version", %{server: server} do
    add_and_check_ledger(server, 2, 12)
    edit_count(40)

    assert {:ok, %TurnResult{status: :committed, reply: %{data: %{count: 40}}}} =
             AgentServer.call(server, Counter.read_signal!())

    assert %CounterState{count: 40, lock_version: 3} = EctoRepo.get!(CounterState, "counter")
    assert [%LedgerEntry{count: 12}] = EctoRepo.all(LedgerEntry)
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I14"
  test "an unchanged proposal still fails when its row is stale", %{server: server} do
    pending = AgentServer.submit(server, add_signal(0), context: %{writer: self()})
    assert_receive {:row_loaded, admission}, 2_000
    edit_count(40)
    send(admission, :write_finished)

    assert {:ok, %TurnResult{status: :failed, error: :stale_ecto_state}} =
             AgentServer.await(pending)

    assert %CounterState{count: 40, lock_version: 2} = EctoRepo.get!(CounterState, "counter")
    assert EctoRepo.all(LedgerEntry) == []
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I14"
  test "a changeset validation failure writes no row or ledger entry", %{server: server} do
    assert {:ok, %TurnResult{status: :failed, error: {:invalid_ecto_state_changes, [count: _issue]}}} =
             AgentServer.call(server, add_signal(-11))

    assert %CounterState{count: 10, lock_version: 1} = EctoRepo.get!(CounterState, "counter")
    assert EctoRepo.all(LedgerEntry) == []
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I4"
  test "admission fails when the canonical row is missing", %{server: server} do
    EctoRepo.delete!(EctoRepo.get!(CounterState, "counter"))

    assert {:ok, %TurnResult{status: :failed, error: :ecto_state_not_found}} =
             AgentServer.call(server, add_signal(2))

    assert EctoRepo.get(CounterState, "counter") == nil
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I6"
  test "a ledger insert failure leaves the committed Counter row intact", %{server: server} do
    observe_effects()
    SQL.query!(EctoRepo, "DROP TABLE turn_ledger")

    assert {:ok, %TurnResult{status: :committed, turn_id: turn_id, reply: %{data: %{count: 13}}}} =
             AgentServer.call(server, add_signal(3))

    assert_receive {:effects, %{turn_id: ^turn_id, status: :error, stage: :after_commit}}, 1_000
    assert %CounterState{count: 13, lock_version: 2} = EctoRepo.get!(CounterState, "counter")
  end

  defp observe_effects do
    event = [:jido, :agent_server, :effects, :stop]
    handler = {__MODULE__, make_ref()}

    :ok = :telemetry.attach(handler, event, fn _, _, metadata, test -> send(test, {:effects, metadata}) end, self())
    on_exit(fn -> :telemetry.detach(handler) end)
  end

  defp add_and_check_ledger(server, by, count) do
    assert {:ok, %TurnResult{status: :committed, turn_id: turn_id, reply: %{data: %{count: ^count}}} = result} =
             AgentServer.call(server, add_signal(by))

    assert %CounterState{count: ^count} = EctoRepo.get!(CounterState, "counter")
    entry = Eventually.eventually(fn -> EctoRepo.get(LedgerEntry, turn_id) end)
    assert %LedgerEntry{agent_id: "counter", count: ^count} = entry
    result
  end

  defp start_counter(config) do
    instance = Keyword.fetch!(config, :name)
    start_supervised!({Jido, config}, id: instance)
    assert {:ok, server} = Jido.start_agent(instance, Counter, id: "counter")
    assert :ok = AgentServer.await_ready(server)
    server
  end

  defp edit_count(count) do
    CounterState
    |> EctoRepo.get!("counter")
    |> CounterState.changeset(%{count: count})
    |> Changeset.optimistic_lock(:lock_version)
    |> EctoRepo.update!()
  end

  defp add_signal(by), do: Counter.add_signal!(%{by: by})
end
