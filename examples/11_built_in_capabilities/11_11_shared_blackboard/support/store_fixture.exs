defmodule Jido.Examples.SharedBlackboard.StoreFixture do
  @moduledoc false

  import ExUnit.Assertions
  import ExUnit.Callbacks

  alias Jido.Test.Persistence.{EctoRepo, EctoSupport}

  def profile(:ets), do: Jido.Persistence.ETS

  def profile(:mnesia) do
    {:ok, _apps} = Application.ensure_all_started(:mnesia)
    table = :"inventory_board_#{System.unique_integer([:positive])}"
    assert {:atomic, :ok} = :mnesia.create_table(table, attributes: [:key, :value], ram_copies: [node()])
    on_exit(fn -> assert {:atomic, :ok} = :mnesia.delete_table(table) end)
    {Jido.Persistence.Mnesia, table: table}
  end

  def profile(:ecto) do
    path = EctoSupport.database_path(:blackboard)
    start_supervised!({EctoRepo, EctoSupport.repo_start_options(path)})
    EctoSupport.migrate!()
    on_exit(fn -> EctoSupport.remove_database(path) end)
    {Jido.Persistence.Ecto, repo: EctoRepo}
  end
end
