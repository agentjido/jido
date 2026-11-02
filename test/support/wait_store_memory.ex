defmodule Jido.Exec.Test.WaitStore.Memory do
  @moduledoc false

  @typedoc "An ETS table owned by the process that called `new/0`."
  @type t :: :ets.tid()

  @doc "Creates a public compare-and-swap table owned by the caller."
  @spec new() :: t()
  def new, do: :ets.new(__MODULE__, [:set, :public, read_concurrency: true])

  @doc "Deletes the in-memory store. Call from its owner."
  @spec close(t()) :: true
  def close(table), do: :ets.delete(table)

  @doc "Loads and decodes the saved Runic snapshot."
  @spec load(term(), t()) :: {:ok, non_neg_integer(), Runic.Workflow.t()} | {:error, term()}
  def load(id, table) do
    case :ets.lookup(table, id) do
      [{^id, revision, _digest, snapshot}] ->
        with {:ok, workflow} <- Runic.Runner.decode_snapshot(snapshot),
             do: {:ok, revision, workflow}

      [] ->
        {:error, :not_found}
    end
  end

  @doc "Saves one native snapshot with an expected revision and idempotent reply recovery."
  @spec save(term(), non_neg_integer(), Runic.Workflow.t(), t()) ::
          {:ok, non_neg_integer()} | {:error, :conflict}
  def save(id, expected, workflow, table) when is_integer(expected) and expected >= 0 do
    snapshot = Runic.Runner.encode_snapshot(workflow)
    digest = :crypto.hash(:sha256, snapshot)

    case :ets.lookup(table, id) do
      [] when expected == 0 ->
        if :ets.insert_new(table, {id, 1, digest, snapshot}),
          do: {:ok, 1},
          else: save(id, expected, workflow, table)

      [{^id, revision, ^digest, _}] when revision in [expected, expected + 1] ->
        {:ok, revision}

      [{^id, ^expected, _old_digest, _old_snapshot}] ->
        match = [
          {{:"$1", expected, :_, :_}, [{:"=:=", :"$1", {:const, id}}],
           [{{:"$1", expected + 1, {:const, digest}, {:const, snapshot}}}]}
        ]

        if :ets.select_replace(table, match) == 1,
          do: {:ok, expected + 1},
          else: save(id, expected, workflow, table)

      _ ->
        {:error, :conflict}
    end
  end
end
