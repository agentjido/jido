defmodule Jido.Blackboard do
  @moduledoc """
  Reads and changes an in-memory board owned by a Jido Agent.

  A board has a name scoped to a local Jido instance. Read a snapshot before
  submitting a patch. Each successful patch returns a new snapshot and
  revision. Revisions from a previous board process cause a conflict.
  """

  alias Jido.Codec.Term

  @default_timeout 500
  @max_timeout 4_294_967_295

  @type snapshot :: %{values: %{optional(String.t()) => term()}, revision: String.t()}
  @type error :: :invalid_request | :conflict | :unavailable | :timeout
  @type timeout_ms :: 1..4_294_967_295

  @doc "Reads the board's current values and revision."
  @spec read(atom(), String.t(), timeout_ms()) :: {:ok, snapshot()} | {:error, error()}
  def read(instance, name, timeout \\ @default_timeout),
    do: request(instance, name, :read, timeout)

  @doc """
  Sets and removes keys in one conditional update.

  A conflict leaves the board unchanged. A timeout can occur after the board
  applies the patch. Read the current snapshot before deciding whether to
  submit another patch.
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
