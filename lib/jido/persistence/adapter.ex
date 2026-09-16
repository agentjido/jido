defmodule Jido.Persistence.Adapter do
  @moduledoc """
  Minimal byte storage contract for durable Jido values.

  An adapter stores binary keys and binary values. It does not inspect domain
  records or own lifecycle policy. Use `Jido.Persistence.Store` for validated
  calls and generic result classification. The application supervises any
  process that the adapter uses.
  """

  @type key :: binary()
  @type value :: binary()
  @type token :: nonempty_binary()
  @type options :: keyword()

  @doc "Validates adapter options before an operation starts."
  @callback validate_options(options()) :: :ok | {:error, term()}

  @doc """
  Gets one value. A missing key returns `{:error, :not_found}`.

  An adapter can return `{:ok, value, token}` when the value and opaque,
  nonempty binary token come from the same read. The Store validates the value
  and passes `{:token, token}` to the next conditional write. The token
  is valid only for this storage key and location. It is not checkpoint data.
  """
  @callback get(key(), options()) ::
              {:ok, value()} | {:ok, value(), token()} | {:error, term()}

  @doc "Stores one value for explicit maintenance and replaces any prior value."
  @callback put(key(), value(), options()) :: :ok | {:error, term()}

  @doc """
  Atomically replaces the expected value, or creates a missing key.

  `:not_found` requires an absent key. A binary requires an exact byte match.
  `{:token, token}` requires the adapter to compare a token from its own prior
  read atomically with this write. Token equality is not byte equality, a
  writer lease, or an activation generation. Adapters that return bytes only
  never receive a token condition from Jido.
  A mismatch returns `{:error, :conflict}` without changing the stored value.
  The comparison and write must be one atomic operation relative to other
  writes and deletes. A separate `get/2` followed by `put/3` is not sufficient.

  Return `{:error, {:rejected, reason}}` only for a documented check that
  finishes before a storage write starts. Return `{:error, :indeterminate}` or
  `{:error, {:indeterminate, reason}}` when the write result is unknown. The
  Store also classifies every other returned error, exception, throw, exit, or
  invalid callback result as indeterminate. The record owner decides what an
  indeterminate write means for its runtime. It must not replay blindly.

  The shared Store requires this callback. `put/3` remains an unconditional
  byte operation for explicit storage maintenance.
  """
  @callback compare_and_swap(key(), :not_found | value() | {:token, token()}, value(), options()) ::
              :ok | {:error, term()}

  @doc "Physically deletes one value for explicit maintenance."
  @callback delete(key(), options()) :: :ok | {:error, term()}

  @optional_callbacks validate_options: 1, put: 3, delete: 2
end
