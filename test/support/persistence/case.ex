defmodule JidoTest.Persistence.Case do
  @moduledoc false

  defmacro __using__(opts) do
    profile = Keyword.fetch!(opts, :profile)

    quote do
      use ExUnit.Case, async: false

      @persistence_profile unquote(profile)
      @moduletag :persistence
      @moduletag persistence_profile: @persistence_profile
      @moduletag persistence_tier: :local
      @moduletag :tmp_dir
      @moduletag timeout: 120_000

      import JidoTest.Case, only: [unique_id: 0, unique_id: 1]

      setup context do
        JidoTest.Persistence.Case.setup(@persistence_profile, context)
      end
    end
  end

  alias JidoTest.Persistence.{EctoRepo, EctoSupport}

  def setup(profile, context) do
    store = start_store!(profile, context)
    suffix = System.unique_integer([:positive])
    jido = :"persistence_conformance_#{profile}_#{suffix}"
    namespace = "persistence-conformance/#{profile}/#{suffix}"

    ExUnit.Callbacks.start_supervised!(
      {Jido, name: jido, namespace: namespace, persistence: store},
      id: jido
    )

    {:ok, store: store, jido: jido, namespace: namespace, persistence_profile: profile}
  end

  defp start_store!(:ets, _context) do
    table = :"persistence_contract_#{System.unique_integer([:positive])}"
    {Jido.Persistence.ETS, table: table}
  end

  defp start_store!(:file, context) do
    {Jido.Persistence.File, path: Path.join(context.tmp_dir, "persistence")}
  end

  defp start_store!(:mnesia, _context) do
    {:ok, _started} = Application.ensure_all_started(:mnesia)
    table = :"persistence_contract_#{System.unique_integer([:positive])}"

    {:atomic, :ok} =
      :mnesia.create_table(table, attributes: [:key, :value], ram_copies: [node()])

    ExUnit.Callbacks.on_exit(fn ->
      case :mnesia.delete_table(table) do
        {:atomic, :ok} -> :ok
        {:aborted, {:no_exists, ^table}} -> :ok
      end
    end)

    {Jido.Persistence.Mnesia, table: table}
  end

  defp start_store!(:ecto_sqlite, _context) do
    path = EctoSupport.database_path(:persistence_contract)

    ExUnit.Callbacks.start_supervised!(
      {EctoRepo, EctoSupport.repo_start_options(path)},
      id: EctoRepo
    )

    EctoSupport.migrate!()
    ExUnit.Callbacks.on_exit(fn -> EctoSupport.remove_database(path) end)
    {Jido.Persistence.Ecto, repo: EctoRepo}
  end
end
