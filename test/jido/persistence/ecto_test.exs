defmodule JidoTest.Persistence.EctoTest do
  use ExUnit.Case, async: false

  alias Jido.Persistence
  alias Jido.Persistence.Ecto, as: EctoPersistence
  alias Jido.Persistence.Ecto.Record
  alias JidoTest.AgentRuntimeFixtures.RuntimeAgent
  alias JidoTest.Persistence.{EctoRepo, EctoSupport}

  defmodule MissingRecord do
    use Ecto.Schema

    @primary_key {:key, :binary, autogenerate: false}
    schema "missing_jido_persistence_records" do
      field(:value, :binary)
      field(:write_token, :binary)
    end
  end

  defmodule ConstrainedRecord do
    use Ecto.Schema

    @primary_key {:key, :binary, autogenerate: false}
    schema "constrained_jido_persistence_records" do
      field(:value, :binary)
      field(:write_token, :binary)
    end
  end

  defmodule InvalidRecord do
    use Ecto.Schema

    @primary_key {:key, :string, autogenerate: false}
    schema "invalid_jido_persistence_records" do
      field(:value, :binary)
      field(:write_token, :binary)
    end
  end

  defmodule UnsupportedRepo do
    def __adapter__, do: __MODULE__.Adapter
  end

  setup_all do
    path = EctoSupport.database_path(:integration)
    start_supervised!({EctoRepo, EctoSupport.repo_start_options(path)})
    EctoSupport.migrate!()
    on_exit(fn -> EctoSupport.remove_database(path) end)
    {:ok, opts: [repo: EctoRepo]}
  end

  test "stores, replaces, and deletes exact bytes", %{opts: opts} do
    key = <<0, 255, 1>>
    first = <<255, 0, 2>>
    second = <<3, 0, 254>>

    assert {:error, :not_found} = EctoPersistence.get(key, opts)
    assert :ok = EctoPersistence.put(key, first, opts)
    assert {:ok, ^first} = EctoPersistence.get(key, opts)

    first_record = EctoRepo.get!(Record, key)
    assert first_record.value == first
    assert byte_size(first_record.write_token) == 16

    assert :ok = EctoPersistence.put(key, second, opts)
    assert {:ok, ^second} = EctoPersistence.get(key, opts)

    second_record = EctoRepo.get!(Record, key)
    assert second_record.write_token != first_record.write_token

    assert :ok = EctoPersistence.delete(key, opts)
    assert :ok = EctoPersistence.delete(key, opts)
    assert {:error, :not_found} = EctoPersistence.get(key, opts)
  end

  test "a same-value CAS succeeds and a conflict changes no row", %{opts: opts} do
    key = "same-value-cas"
    value = <<0, 1, 0, 255>>

    assert :ok = EctoPersistence.compare_and_swap(key, :not_found, value, opts)
    first_token = EctoRepo.get!(Record, key).write_token

    assert :ok = EctoPersistence.compare_and_swap(key, value, value, opts)
    second_token = EctoRepo.get!(Record, key).write_token
    assert second_token != first_token

    assert {:error, :conflict} =
             EctoPersistence.compare_and_swap(key, <<99>>, <<2>>, opts)

    assert %{value: ^value, write_token: ^second_token} = EctoRepo.get!(Record, key)
  end

  test "works through the complete Jido persistence boundary", %{opts: opts} do
    store = {EctoPersistence, opts}
    agent = RuntimeAgent.new!(id: "ecto-agent", state: %{events: [:saved], ticks: 2})

    assert :ok =
             Persistence.save_agent(store, agent,
               instance: __MODULE__,
               revision: 4
             )

    assert {:ok, ^agent, 4} =
             Persistence.load_agent_with_revision(store, RuntimeAgent, agent.id,
               instance: __MODULE__
             )

    assert :ok =
             Persistence.delete_agent(store, RuntimeAgent, agent.id, instance: __MODULE__)

    assert {:error, :deleted} =
             Persistence.load_agent(store, RuntimeAgent, agent.id, instance: __MODULE__)
  end

  test "validates the repo, schema, and repository options", %{opts: opts} do
    assert :ok = EctoPersistence.validate_options(opts)

    assert {:ok, {EctoPersistence, ^opts}} =
             Persistence.resolve_config({EctoPersistence, opts}, nil)

    for invalid <- [
          [],
          [repo: UnsupportedRepo],
          [repo: EctoRepo, schema: InvalidRecord],
          [repo: EctoRepo, repo_options: :invalid],
          [repo: EctoRepo, repo_options: [on_conflict: :nothing]],
          [repo: EctoRepo, unknown: true],
          [:not_keyword]
        ] do
      assert {:error, _reason} = EctoPersistence.validate_options(invalid)
    end
  end

  test "classifies database failures during CAS as indeterminate", %{opts: opts} do
    missing_opts = Keyword.put(opts, :schema, MissingRecord)

    assert {:error, {:ecto, _, _message}} = EctoPersistence.get("key", missing_opts)

    assert {:error, {:indeterminate, {:ecto, _, _message}}} =
             EctoPersistence.compare_and_swap("key", :not_found, "value", missing_opts)
  end

  test "does not classify an unrelated unique constraint as a key conflict", %{opts: opts} do
    constrained_opts = Keyword.put(opts, :schema, ConstrainedRecord)

    assert :ok =
             EctoPersistence.compare_and_swap("first-key", :not_found, "value", constrained_opts)

    assert {:error, {:indeterminate, {:ecto, _, _message}}} =
             EctoPersistence.compare_and_swap(
               "second-key",
               :not_found,
               "value",
               constrained_opts
             )
  end
end
