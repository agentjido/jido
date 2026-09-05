defmodule Jido.Persistence do
  @moduledoc """
  Saves and restores portable Agent checkpoints through a persistence adapter.

  Persistence owns Agent record keys, encoding, validation, and adapter fault
  containment. Adapters only store binary keys and values.

  Agent Servers store their `state_version` as the record revision. Each
  successful Turn writes one new revision, including an identical-state result.
  A failure before commit leaves the stored revision unchanged. A failure in
  post-commit work does not undo the stored revision. Restore retains it.
  Direct `save_agent/3` calls use the revision supplied in their options.

  Caller execution context is not part of the checkpoint. Only values that
  application code puts in portable Agent or Plugin state can be stored.
  """

  alias Jido.Agent
  alias Jido.Error

  @format_version 1
  @key_prefix "jido:agent:v1:"

  @type adapter_config :: {module(), keyword()} | module() | nil | false

  @doc "Normalizes an adapter declaration."
  @spec normalize_adapter(adapter_config()) :: {module(), keyword()} | nil
  def normalize_adapter(nil), do: nil
  def normalize_adapter(false), do: nil

  def normalize_adapter({adapter, opts}) when is_atom(adapter) and is_list(opts),
    do: {adapter, opts}

  def normalize_adapter(adapter) when is_atom(adapter), do: {adapter, []}

  def normalize_adapter(config) do
    raise ArgumentError, "invalid Jido persistence adapter: #{inspect(config)}"
  end

  @doc false
  @spec resolve_config(term(), atom() | nil) ::
          {:ok, {module(), keyword()} | nil} | {:error, term()}
  def resolve_config(:inherit, jido), do: resolve_instance_config(jido)
  def resolve_config(nil, _jido), do: {:ok, nil}
  def resolve_config(false, _jido), do: {:ok, nil}

  def resolve_config(config, _jido) do
    config
    |> normalize_adapter_result()
    |> validate_adapter_result()
  end

  @doc """
  Saves one Agent checkpoint with an atomic revision check.

  `:revision` defaults to zero. A stored revision cannot decrease. At the same
  revision, only the same record can be saved again. Changed state needs a
  greater revision. Conflicting writes return `{:error, :conflict}`.

  Set `:expected_revision` to the revision read by the caller to reject writes
  based on stale state, even when the proposed revision is greater. Zero also
  accepts a missing record for the first commit. Without this option, a direct
  save accepts any older stored revision, or a missing record.

  The Server always supplies its current revision as `:expected_revision`.
  A failed check does not replace the stored record. Deletion or expiry removes
  revision history; this check is not a writer lease across record lifetimes.
  """
  @spec save_agent(adapter_config() | atom(), Agent.t(), keyword()) ::
          :ok | {:error, term()}
  def save_agent(source, %Agent{} = agent, opts \\ []) when is_list(opts) do
    protect(:compare_and_swap, fn ->
      with {:ok, {adapter, adapter_opts}, instance} <- resolve_source(source, opts),
           {:ok, record} <- build_record(agent, instance, opts),
           {:ok, expected_revision} <- expected_revision(opts),
           {:ok, expected_value} <-
             current_value(adapter, adapter_opts, record, expected_revision),
           {:ok, value} <- encode_record(record),
           :ok <-
             adapter_compare_and_swap(
               adapter,
               agent_key(record),
               expected_value,
               value,
               adapter_opts
             ) do
        :ok
      end
    end)
  end

  @doc "Loads and restores one Agent value."
  @spec load_agent(adapter_config() | atom(), module(), String.t(), keyword()) ::
          {:ok, Agent.t()} | {:error, term()}
  def load_agent(source, agent_module, agent_id, opts \\ [])
      when is_atom(agent_module) and is_binary(agent_id) and is_list(opts) do
    case load_agent_with_revision(source, agent_module, agent_id, opts) do
      {:ok, agent, _revision} -> {:ok, agent}
      {:error, _reason} = error -> error
    end
  end

  @doc false
  @spec load_agent_with_revision(adapter_config() | atom(), module(), String.t(), keyword()) ::
          {:ok, Agent.t(), non_neg_integer()} | {:error, term()}
  def load_agent_with_revision(source, agent_module, agent_id, opts \\ [])
      when is_atom(agent_module) and is_binary(agent_id) and is_list(opts) do
    protect(:get, fn ->
      with {:ok, {adapter, adapter_opts}, instance} <- resolve_source(source, opts),
           partition = Keyword.get(opts, :partition),
           key = agent_key(instance, agent_module, agent_id, partition),
           {:ok, value} <- adapter_get(adapter, key, adapter_opts),
           {:ok, record} <- decode_record(value),
           :ok <- validate_record(record, instance, agent_module, agent_id, partition),
           {:ok, agent} <-
             Agent.restore(agent_module, record.checkpoint, restore_context(record)),
           :ok <- validate_restored_identity(agent, agent_module, agent_id) do
        {:ok, agent, record.revision}
      end
    end)
  end

  @doc "Deletes one stored Agent checkpoint."
  @spec delete_agent(adapter_config() | atom(), module(), String.t(), keyword()) ::
          :ok | {:error, term()}
  def delete_agent(source, agent_module, agent_id, opts \\ [])
      when is_atom(agent_module) and is_binary(agent_id) and is_list(opts) do
    protect(:delete, fn ->
      with {:ok, {adapter, adapter_opts}, instance} <- resolve_source(source, opts) do
        key = agent_key(instance, agent_module, agent_id, Keyword.get(opts, :partition))
        adapter_delete(adapter, key, adapter_opts)
      end
    end)
  end

  @doc false
  @spec agent_key(atom() | nil, module(), String.t(), term()) :: binary()
  def agent_key(instance, agent_module, agent_id, partition \\ nil)
      when (is_atom(instance) or is_nil(instance)) and is_atom(agent_module) and
             is_binary(agent_id) do
    identity = :erlang.term_to_binary({instance, agent_module, partition, agent_id})
    @key_prefix <> Base.url_encode64(identity, padding: false)
  end

  defp resolve_instance_config(jido) when is_atom(jido) and not is_nil(jido) do
    if function_exported?(jido, :__jido_persistence__, 0) do
      jido.__jido_persistence__()
      |> normalize_adapter_result()
      |> validate_adapter_result()
    else
      {:ok, nil}
    end
  rescue
    error -> {:error, {:invalid_persistence_config, error}}
  end

  defp resolve_instance_config(_jido), do: {:ok, nil}

  defp resolve_source(source, opts) when is_atom(source) and not is_nil(source) do
    if function_exported?(source, :__jido_persistence__, 0) do
      with {:ok, config} <- resolve_instance_config(source),
           {:ok, config} <- require_adapter(config) do
        {:ok, config, Keyword.get(opts, :instance, source)}
      end
    else
      with {:ok, config} <- resolve_config(source, nil),
           {:ok, config} <- require_adapter(config) do
        {:ok, config, Keyword.get(opts, :instance)}
      end
    end
  end

  defp resolve_source(source, opts) do
    with {:ok, config} <- resolve_config(source, nil),
         {:ok, config} <- require_adapter(config) do
      {:ok, config, Keyword.get(opts, :instance)}
    end
  end

  defp require_adapter(nil), do: {:error, :persistence_not_configured}
  defp require_adapter(config), do: {:ok, config}

  defp normalize_adapter_result(config) do
    {:ok, normalize_adapter(config)}
  rescue
    error -> {:error, {:invalid_persistence_config, error}}
  end

  defp validate_adapter_result({:ok, nil}), do: {:ok, nil}

  defp validate_adapter_result({:ok, {adapter, _opts} = config}) do
    with {:module, ^adapter} <- Code.ensure_loaded(adapter),
         true <- function_exported?(adapter, :get, 2),
         true <- function_exported?(adapter, :put, 3),
         true <- function_exported?(adapter, :compare_and_swap, 4),
         true <- function_exported?(adapter, :delete, 2) do
      {:ok, config}
    else
      _value -> {:error, {:invalid_persistence_adapter, adapter}}
    end
  end

  defp validate_adapter_result({:error, _reason} = error), do: error

  defp expected_revision(opts) do
    case Keyword.fetch(opts, :expected_revision) do
      :error -> {:ok, :any}
      {:ok, revision} when is_integer(revision) and revision >= 0 -> {:ok, revision}
      {:ok, revision} -> {:error, {:invalid_expected_revision, revision}}
    end
  end

  defp current_value(adapter, opts, record, expected_revision) do
    case adapter_get(adapter, agent_key(record), opts) do
      {:error, :not_found} when expected_revision in [:any, 0] ->
        {:ok, :not_found}

      {:error, :not_found} ->
        {:error, :conflict}

      {:ok, value} ->
        with {:ok, current} <- decode_record(value),
             :ok <-
               validate_record(
                 current,
                 record.instance,
                 record.agent_module,
                 record.agent_id,
                 record.partition
               ),
             :ok <- check_revision(current, record, expected_revision) do
          {:ok, value}
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp check_revision(current, record, expected_revision) do
    cond do
      expected_revision != :any and current.revision != expected_revision -> {:error, :conflict}
      record.revision > current.revision -> :ok
      record === current -> :ok
      true -> {:error, :conflict}
    end
  end

  defp build_record(agent, instance, opts) do
    partition = Keyword.get(opts, :partition)
    revision = Keyword.get(opts, :revision, 0)
    reason = Keyword.get(opts, :reason, :manual)

    context = %{
      instance: instance,
      partition: partition,
      revision: revision,
      reason: reason
    }

    with true <- is_integer(revision) and revision >= 0,
         {:ok, checkpoint} <- Agent.checkpoint(agent, context),
         true <- is_map(checkpoint) do
      record = %{
        format: @format_version,
        kind: :agent,
        instance: instance,
        agent_module: agent.module,
        agent_id: agent.id,
        partition: partition,
        revision: revision,
        checkpoint: checkpoint
      }

      if portable_term?(record),
        do: {:ok, record},
        else: {:error, {:invalid_checkpoint, :non_portable_term}}
    else
      false -> {:error, {:invalid_checkpoint, :shape}}
      {:error, _reason} = error -> error
    end
  end

  defp encode_record(record) do
    {:ok, :erlang.term_to_binary(record)}
  rescue
    error -> {:error, {:checkpoint_encode_failed, error}}
  end

  defp decode_record(value) when is_binary(value) do
    {:ok, :erlang.binary_to_term(value, [:safe])}
  rescue
    ArgumentError -> {:error, :invalid_persistence_record}
  end

  defp validate_record(record, instance, agent_module, agent_id, partition)
       when is_map(record) do
    cond do
      Map.get(record, :format) != @format_version ->
        {:error, {:invalid_persistence_record, :format}}

      Map.get(record, :kind) != :agent ->
        {:error, {:invalid_persistence_record, :kind}}

      Map.get(record, :instance) != instance ->
        {:error, {:invalid_persistence_record, :instance}}

      Map.get(record, :agent_module) != agent_module ->
        {:error, {:invalid_persistence_record, :agent_module}}

      Map.get(record, :agent_id) != agent_id ->
        {:error, {:invalid_persistence_record, :agent_id}}

      Map.get(record, :partition) != partition ->
        {:error, {:invalid_persistence_record, :partition}}

      not is_integer(Map.get(record, :revision)) or Map.get(record, :revision) < 0 ->
        {:error, {:invalid_persistence_record, :revision}}

      not is_map(Map.get(record, :checkpoint)) ->
        {:error, {:invalid_persistence_record, :checkpoint}}

      not portable_term?(record) ->
        {:error, {:invalid_persistence_record, :non_portable_term}}

      true ->
        :ok
    end
  end

  defp validate_record(_record, _instance, _agent_module, _agent_id, _partition),
    do: {:error, {:invalid_persistence_record, :shape}}

  defp validate_restored_identity(%Agent{module: module, id: id}, module, id), do: :ok

  defp validate_restored_identity(_agent, _module, _id),
    do: {:error, {:invalid_persistence_record, :checkpoint_identity}}

  defp restore_context(record) do
    %{
      instance: record.instance,
      partition: record.partition,
      revision: record.revision,
      reason: :restore
    }
  end

  defp agent_key(record) do
    agent_key(record.instance, record.agent_module, record.agent_id, record.partition)
  end

  defp adapter_get(adapter, key, opts) do
    case adapter.get(key, opts) do
      {:ok, value} when is_binary(value) -> {:ok, value}
      {:error, _reason} = error -> error
      result -> invalid_adapter_result(:get, result)
    end
  end

  defp adapter_compare_and_swap(adapter, key, expected, value, opts) do
    case adapter.compare_and_swap(key, expected, value, opts) do
      :ok -> :ok
      {:error, _reason} = error -> error
      result -> invalid_adapter_result(:compare_and_swap, result)
    end
  end

  defp adapter_delete(adapter, key, opts) do
    case adapter.delete(key, opts) do
      :ok -> :ok
      {:error, _reason} = error -> error
      result -> invalid_adapter_result(:delete, result)
    end
  end

  defp protect(operation, fun) do
    fun.()
  rescue
    error -> persistence_failure(operation, :error, error)
  catch
    kind, reason -> persistence_failure(operation, kind, reason)
  end

  defp invalid_adapter_result(operation, result) do
    {:error,
     Error.execution_error("Persistence adapter returned an invalid result",
       details: %{operation: operation, result: result}
     )}
  end

  defp persistence_failure(operation, kind, reason) do
    {:error,
     Error.execution_error("Persistence adapter operation failed",
       details: %{operation: operation, kind: kind, reason: reason}
     )}
  end

  defp portable_term?(term)
       when is_pid(term) or is_reference(term) or is_port(term) or is_function(term),
       do: false

  defp portable_term?(term) when is_map(term) do
    term
    |> Map.to_list()
    |> Enum.all?(fn {key, value} -> portable_term?(key) and portable_term?(value) end)
  end

  defp portable_term?(term) when is_tuple(term),
    do: term |> Tuple.to_list() |> Enum.all?(&portable_term?/1)

  defp portable_term?([]), do: true

  defp portable_term?([head | tail]),
    do: portable_term?(head) and portable_term?(tail)

  defp portable_term?(_term), do: true
end
