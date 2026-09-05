defmodule Jido.Persistence.Adapter do
  @moduledoc """
  Minimal byte storage contract for durable Jido values.

  An adapter stores binary keys and binary values. It does not inspect Agent
  checkpoints or own lifecycle policy. The application supervises any process
  that the adapter uses.
  """

  @type key :: binary()
  @type value :: binary()
  @type options :: keyword()

  @doc "Gets one value. A missing key returns `{:error, :not_found}`."
  @callback get(key(), options()) :: {:ok, value()} | {:error, term()}

  @doc "Stores one value and replaces any value for the same key."
  @callback put(key(), value(), options()) :: :ok | {:error, term()}

  @doc """
  Atomically replaces the expected value, or creates a missing key.

  `:not_found` requires an absent key. A binary requires an exact byte match.
  A mismatch returns `{:error, :conflict}` without changing the stored value.
  The comparison and write must be one atomic operation relative to other
  writes and deletes. A separate `get/2` followed by `put/3` is not sufficient.

  Return `{:error, :indeterminate}` or `{:error, {:indeterminate, reason}}`
  when the write result is unknown. Other returned errors confirm that this
  operation did not store the proposed value. Exceptions and invalid callback
  replies are also treated as uncertain. The Server stops an uncertain writer
  before another Action can run. Restore from storage before retrying.

  Agent checkpoint saves require this callback. `put/3` remains an
  unconditional byte operation for explicit storage maintenance.
  """
  @callback compare_and_swap(key(), :not_found | value(), value(), options()) ::
              :ok | {:error, term()}

  @doc "Deletes one value. Deleting a missing key returns `:ok`."
  @callback delete(key(), options()) :: :ok | {:error, term()}
end
