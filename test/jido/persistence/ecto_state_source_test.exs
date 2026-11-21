defmodule Jido.Persistence.EctoStateSourceTest do
  use ExUnit.Case, async: false

  alias Jido.AgentServer
  alias Jido.Persistence.{Record, Store}
  alias Jido.Persistence.Codec.Term
  alias Jido.Persistence.Ecto, as: EctoPersistence
  alias Jido.Persistence.StateSource.Source
  alias Jido.Test.Persistence.{EctoRepo, EctoSupport}

  defmodule PostgresRepo do
    use Ecto.Repo, otp_app: :jido, adapter: Ecto.Adapters.Postgres
  end

  defmodule CounterRow do
    use Ecto.Schema

    @primary_key {:id, :string, autogenerate: false}
    schema "state_source_counters" do
      field(:count, :integer)
      field(:lock_version, :integer)
    end
  end

  defmodule Migration do
    use Ecto.Migration

    def change do
      create table(:state_source_counters, primary_key: false) do
        add(:id, :string, primary_key: true)
        add(:count, :integer, null: false)
        add(:lock_version, :integer, null: false)
      end

      Jido.Persistence.Ecto.Migration.up(version: 1)
    end
  end

  defmodule RowSource do
    use Jido.Plugin, id: "test/plain-ecto-row"

    @behaviour Jido.Persistence.StateSource

    import Ecto.Query

    alias Jido.Joi

    @impl true
    def state_source(:counter, _env) do
      {Joi.object(%{count: Joi.required(Joi.integer()), lock_version: Joi.required(Joi.integer())}), CounterRow}
    end

    @impl true
    def startup_id(CounterRow, id) when is_binary(id) and id != "", do: {:ok, id}
    def startup_id(CounterRow, _id), do: {:error, :counter_id_required}

    @impl true
    def open(CounterRow, context, :create, agent, create) do
      with {:ok, row} <- read(context, agent.id), do: create.(project(row))
    end

    def open(CounterRow, _context, :restore, _agent, restore), do: restore.(fn _, _ -> {:ok, %{}} end)

    @impl true
    def refresh(CounterRow, context, agent) do
      with {:ok, row} <- read(context, agent.id), do: {:ok, project(row)}
    end

    @impl true
    def apply_state(CounterRow, _context, before, candidate, repo) do
      id = before.id
      version = before.state.lock_version
      query = from(row in CounterRow, where: row.id == ^id and row.lock_version == ^version)
      count = candidate.state.count

      case repo.update_all(query, set: [count: count], inc: [lock_version: 1]) do
        {1, nil} ->
          canonical = repo.get!(CounterRow, id)
          owner = Process.whereis(Jido.Persistence.EctoStateSourceTest)
          projected = project(canonical)
          send(owner, {:domain_write, projected, repo.in_transaction?()})
          projected = if count == 7, do: Map.put(projected, :owned, 99), else: projected
          {:ok, projected, fn -> notify(owner, repo, count) end}

        {0, nil} ->
          {:error, {:rejected, :stale_counter}}
      end
    end

    defp notify(owner, repo, 8) do
      send(owner, {:db_committed, self(), repo.in_transaction?()})

      receive do
        :reply -> :ok
      after
        10_000 -> raise "The test did not stop the activation after the commit"
      end
    end

    defp notify(owner, repo, _count), do: send(owner, {:post_commit, repo.in_transaction?()})

    defp read(%{persistence: %{store: {_, opts}}}, id) do
      repo = Keyword.fetch!(opts, :repo)

      case repo.get(CounterRow, id) do
        %CounterRow{} = row -> {:ok, row}
        nil -> {:error, :counter_not_found}
      end
    end

    defp project(row), do: Map.take(row, [:count, :lock_version])
  end

  defmodule SetCount do
    use Jido.Action,
      name: "ecto_state_source_set_count",
      schema: Jido.Joi.object(%{count: Jido.Joi.integer(), pause: Jido.Joi.boolean()})

    @impl true
    def run(%{count: count} = params, context) do
      if params[:pause] do
        send(Process.whereis(Jido.Persistence.EctoStateSourceTest), {:evaluating, self()})

        receive do
          :continue -> :ok
        after
          5_000 -> raise "The test did not resume the Turn"
        end
      end

      {:ok, %{context.agent_state | count: count}}
    end
  end

  defmodule OtherPlugin do
    use Jido.Plugin

    @impl true
    def state_spec(_), do: {:owned, Jido.Joi.integer() |> Jido.Joi.default(0)}
  end

  defmodule Counter do
    use Jido.Agent, name: "ecto_state_source_counter", plugins: [RowSource, OtherPlugin]

    state do
      state_source(RowSource, :counter)
    end

    routes do
      route "counter.set", SetCount
    end
  end

  describe "SQLite" do
    setup do
      path = EctoSupport.database_path(:state_source)
      options = Keyword.put(EctoSupport.repo_start_options(path), :pool_size, 1)
      start_supervised!({EctoRepo, options})
      on_exit(fn -> EctoSupport.remove_database(path) end)
      setup_counter(EctoRepo)
    end

    test("commits the Ecto row and canonical checkpoint together", context, do: commit(context))

    test("rolls back an Ecto row write on checkpoint conflict", context, do: rollback(context))

    test("rolls back a source write that tries to change another Plugin's fields", context, do: foreign_field(context))

    test("recovers a retained result after a lost commit reply", context, do: recover(context))
  end

  describe "PostgreSQL" do
    if is_nil(System.get_env("ASH_JIDO_POSTGRES_PORT")) do
      @describetag skip: "Set ASH_JIDO_POSTGRES_PORT to run PostgreSQL tests"
    end

    setup do
      start_postgres()
      setup_counter(PostgresRepo)
    end

    test("commits the Ecto row and canonical checkpoint together", context, do: commit(context))

    test("rolls back an Ecto row write on checkpoint conflict", context, do: rollback(context))

    test("rolls back a source write that tries to change another Plugin's fields", context, do: foreign_field(context))

    test("recovers a retained result after a lost commit reply", context, do: recover(context))
  end

  defp setup_counter(repo) do
    Process.register(self(), __MODULE__)
    :ok = Ecto.Migrator.up(repo, 2_026_112_101, Migration, log: false)
    row = repo.insert!(%CounterRow{id: "counter", count: 2, lock_version: 1})

    store = {EctoPersistence, repo: repo}

    start_runtime(store)
    {:ok, address} = Jido.agent_address(Runtime, row.id)
    {:ok, server} = Jido.start_agent(Runtime, Counter, state: %Source{provider: RowSource, input: row.id})
    %{repo: repo, store: store, address: address, server: server}
  end

  defp start_runtime(store) do
    start_supervised!({Jido, name: Runtime, namespace: "test/plain-ecto-row", persistence: store})
  end

  defp commit(%{repo: repo, server: server, address: address}) do
    assert %{agent: %{state: %{count: 2, lock_version: 1}}, agent_revision: 0, persistence_revision: 0} =
             AgentServer.snapshot(server)

    assert {:ok, %{status: :committed, turn_id: turn_id, agent_revision: 1, persistence_revision: 2}} =
             AgentServer.call(server, signal(12))

    assert_receive {:domain_write, %{count: 12, lock_version: 2}, true}
    assert_receive {:post_commit, false}
    assert %{count: 12, lock_version: 2} = repo.get!(CounterRow, address.id)
    assert %{agent: %{state: %{count: 12, lock_version: 2}}} = AgentServer.snapshot(server)

    assert {:ok, %{state: %{count: 12, lock_version: 2}}, 2, 1, %{id: ^turn_id, status: :completed}} =
             Jido.Persistence.load_agent_address(Runtime, address)
  end

  defp rollback(%{repo: repo, store: store, address: address, server: server}) do
    turn = Task.async(fn -> AgentServer.call(server, signal(6, true)) end)
    assert_receive {:evaluating, executor}, 2_000

    key = Record.agent_key(address)
    assert {:ok, bytes, condition} = Store.read(store, key)
    assert {:ok, record} = Term.decode(bytes, [])
    assert {:ok, competing} = Term.encode(Map.update!(record, :rev, &(&1 + 1)))
    assert :ok = Store.compare_and_swap(store, key, condition, competing)

    send(executor, :continue)
    assert {:ok, %{status: :uncertain}} = Task.await(turn)
    assert_receive {:domain_write, %{count: 6, lock_version: 2}, true}
    refute_received {:post_commit, _}
    assert %{count: 2, lock_version: 1} = repo.get!(CounterRow, address.id)
    assert {:ok, ^competing, _} = Store.read(store, key)
  end

  defp foreign_field(%{repo: repo, server: server, address: address}) do
    assert {:ok, %{status: :failed, error: {:state_source_undeclared_fields, [:owned]}}} =
             AgentServer.call(server, signal(7))

    assert_receive {:domain_write, %{count: 7, lock_version: 2}, true}
    refute_received {:post_commit, _}
    assert %{count: 2, lock_version: 1} = repo.get!(CounterRow, address.id)
    assert %{agent: %{state: %{count: 2, owned: 0}}} = AgentServer.snapshot(server)
  end

  defp recover(%{repo: repo, store: store, server: server, address: address}) do
    {caller, caller_monitor} =
      spawn_monitor(fn ->
        Runtime
        |> Jido.submit(address, signal(8), turn_id: "lost-ecto-reply", result_handoff: true)
        |> AgentServer.await()
      end)

    assert_receive {:db_committed, writer, false}, 2_000
    assert %{count: 8, lock_version: 2} = repo.get!(CounterRow, address.id)
    assert %{agent: %{state: %{count: 2, lock_version: 1}}} = AgentServer.snapshot(server)
    writer_monitor = Process.monitor(writer)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^caller_monitor, :process, ^caller, :killed}, 2_000

    stop_supervised!(Runtime)
    assert_receive {:DOWN, ^writer_monitor, :process, ^writer, _reason}, 2_000
    refute_received {:post_commit, _}

    start_runtime(store)

    assert {:ok, %{status: :committed, turn_id: "lost-ecto-reply", agent_revision: 1}} =
             Jido.turn_result(Runtime, address, "lost-ecto-reply")

    assert {:ok, restored} = Jido.activate_agent(Runtime, address)
    assert restored != server
    assert %{agent: %{state: %{count: 8, lock_version: 2}}} = AgentServer.snapshot(restored)
    assert %{count: 8, lock_version: 2} = repo.get!(CounterRow, address.id)
  end

  defp signal(count, pause \\ false),
    do: Jido.Signal.new!("counter.set", %{count: count, pause: pause}, source: "/counter")

  defp start_postgres do
    database = "jido_ecto_state_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    options = [
      hostname: "127.0.0.1",
      port: String.to_integer(System.fetch_env!("ASH_JIDO_POSTGRES_PORT")),
      username: "postgres",
      database: "postgres"
    ]

    postgres_admin!("CREATE DATABASE #{database}", options)
    on_exit(fn -> postgres_admin!("DROP DATABASE #{database}", options) end)
    start_supervised!({PostgresRepo, Keyword.merge(options, database: database, pool_size: 4, log: false)})
  end

  defp postgres_admin!(sql, options) do
    {:ok, connection} = Postgrex.start_link(options)

    try do
      Postgrex.query!(connection, sql, [])
    after
      GenServer.stop(connection)
    end
  end
end
