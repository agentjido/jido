defmodule Jido.Blackboard do
  @moduledoc """
  Reads and changes a named board owned by a Jido Agent.

  A board has a name scoped to a local Jido instance. Read a snapshot before
  submitting a patch. Each successful patch returns a new snapshot and
  revision. Revisions from a previous board process cause a conflict.
  """

  alias Jido.Agent.Address
  alias Jido.Blackboard.Record
  alias Jido.Codec.Term

  @default_timeout 500
  @max_timeout 4_294_967_295

  @type snapshot :: %{values: %{optional(String.t()) => term()}, revision: String.t()}
  @type error :: :invalid_request | :conflict | :unavailable | :timeout | :indeterminate
  @type timeout_ms :: 1..4_294_967_295

  @doc "Reads the board's current values and revision."
  @spec read(atom(), String.t(), timeout_ms()) :: {:ok, snapshot()} | {:error, error()}
  def read(instance, name, timeout \\ @default_timeout),
    do: request(instance, name, :read, timeout)

  @doc """
  Sets and removes keys in one conditional update.

  A conflict leaves the board unchanged. A timeout or an indeterminate Store
  result can occur after the board applies the patch. Read the current
  snapshot before deciding whether to submit another patch.
  """
  @spec patch(atom(), String.t(), String.t(), map(), [String.t()], timeout_ms()) ::
          {:ok, snapshot()} | {:error, error()}
  def patch(instance, name, revision, put, delete \\ [], timeout \\ @default_timeout)

  def patch(instance, name, revision, put, delete, timeout)
      when is_binary(revision) and byte_size(revision) > 0 do
    with :ok <- validate_changes(put, delete) do
      request(instance, name, {:patch, revision, put, delete}, timeout)
    end
  end

  def patch(_instance, _name, _revision, _put, _delete, _timeout), do: {:error, :invalid_request}

  @doc """
  Retires a saved board after its owner stops.

  Pass the owner's stable Address and board name. Deletion writes a tombstone.
  A second delete of the same record succeeds. Use a new owner ID to start a
  new board with the same name.
  """
  @spec delete(atom(), Address.t(), String.t()) :: :ok | {:error, error() | :running | :not_found}
  def delete(instance, %Address{} = address, name)
      when is_atom(instance) and not is_nil(instance) and is_binary(name) and byte_size(name) > 0 do
    with :ok <- validate_owner_address(instance, address),
         {:ok, record} <- Record.configure(instance, address, name) do
      with_lifecycle_lock(instance, name, fn ->
        if board_running?(instance, name) do
          {:error, :running}
        else
          Record.delete(record)
        end
      end)
    else
      {:error, :invalid_request} = error -> error
      {:error, _reason} -> {:error, :unavailable}
    end
  end

  def delete(_instance, _address, _name), do: {:error, :invalid_request}

  defp board_running?(instance, name) do
    # A stopped board can remain in the Registry until its exit is processed.
    case Registry.lookup(Jido.Blackboard.Registry, {instance, name}) do
      [{pid, _value}] -> Process.alive?(pid)
      [] -> false
    end
  end

  defp validate_owner_address(instance, address) do
    case Jido.agent_address(instance, address.id, partition: address.partition) do
      {:ok, ^address} -> :ok
      _invalid -> {:error, :invalid_request}
    end
  end

  @doc false
  def validate_changes(put, delete) when is_non_struct_map(put) and is_list(delete) do
    if Enum.all?(Map.keys(put), &is_binary/1) and
         Term.valid?(put) and
         Term.valid?(delete) and
         Enum.all?(delete, &(is_binary(&1) and not Map.has_key?(put, &1))) do
      :ok
    else
      {:error, :invalid_request}
    end
  end

  def validate_changes(_put, _delete), do: {:error, :invalid_request}

  @doc false
  def via(instance, name), do: {:via, Registry, {Jido.Blackboard.Registry, {instance, name}}}

  @doc false
  def with_lifecycle_lock(instance, name, operation) do
    # Serialize registration and retirement without blocking reads or writes.
    registry = Jido.Blackboard.Registry
    key = {:lifecycle, instance, name}

    case Registry.register(registry, key, nil) do
      {:ok, _pid} ->
        try do
          operation.()
        after
          Registry.unregister(registry, key)
        end

      {:error, {:already_registered, _pid}} ->
        {:error, :unavailable}
    end
  end

  defp request(instance, name, message, timeout)
       when is_atom(instance) and not is_nil(instance) and is_binary(name) and byte_size(name) > 0 and
              timeout in 1..@max_timeout do
    GenServer.call(via(instance, name), message, timeout)
  rescue
    ArgumentError -> {:error, :unavailable}
  catch
    :exit, {:timeout, _call} -> {:error, :timeout}
    :exit, _reason -> {:error, :unavailable}
  end

  defp request(_instance, _name, _message, _timeout), do: {:error, :invalid_request}
end
