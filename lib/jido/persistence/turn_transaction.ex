defmodule Jido.Persistence.TurnTransaction do
  @moduledoc false

  alias Jido.Persistence.Config

  @type binding :: {module(), term()}
  @type result :: {:ok, term()} | {:error, term()}

  @doc """
  Loads or writes domain state with the Agent checkpoint in the same
  transaction. Call the supplied operation once in the transaction process.
  Roll back on an error and return success only after the transaction commits.
  Reject a source that cannot use the same transaction as the checkpoint.
  """
  @callback transact(Config.t(), binding(), (transaction :: term() -> result())) :: result()

  def run(nil, _binding, _operation),
    do:
      Jido.Error.validation_result(
        :state_provider_requires_persistence,
        [:persistence],
        "Configure persistence to use this Agent's state source."
      )

  def run(%Config{store: {adapter, _options}} = config, binding, operation) do
    if function_exported?(adapter, :transact, 3) do
      case adapter.transact(config, binding, operation) do
        {:ok, _} = success -> success
        {:error, _} = error -> error
        _other -> {:error, :indeterminate}
      end
    else
      {:error, :state_source_transaction_unsupported}
    end
  rescue
    _error -> {:error, :indeterminate}
  catch
    _kind, _reason -> {:error, :indeterminate}
  end
end
