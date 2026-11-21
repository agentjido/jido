defmodule Jido.Persistence.TurnTransaction do
  @moduledoc false

  alias Jido.Persistence.Config

  @type binding :: {module(), term()}
  @type result :: {:ok, term()} | {:error, term()}

  @doc """
  Runs a successful Turn's state write and checkpoint save in the same
  transaction. Call the supplied operation once in the transaction process.
  Roll back on an error and return success only after the transaction commits.
  Reject a source that cannot use the same transaction as the checkpoint.
  """
  @callback transact(Config.t(), binding(), (transaction :: term() -> result())) :: result()

  def supported(%Config{store: {adapter, _options}}) do
    if function_exported?(adapter, :transact, 3),
      do: :ok,
      else: {:error, :state_source_transaction_unsupported}
  end

  def run(%Config{store: {adapter, _options}} = config, binding, operation) do
    with :ok <- supported(config) do
      case adapter.transact(config, binding, operation) do
        {:ok, _} = success -> success
        {:error, _} = error -> error
        _other -> {:error, :indeterminate}
      end
    end
  rescue
    _error -> {:error, :indeterminate}
  catch
    _kind, _reason -> {:error, :indeterminate}
  end
end
