defmodule Jido.Persistence do
  @moduledoc """
  Saves and restores portable Agent checkpoints through a persistence adapter.

  Persistence owns Agent record keys, encoding, validation, and adapter fault
  containment. Adapters only store binary keys and values.

  Durable values are versioned active records or compact tombstones. An active
  record does not prove that an Agent process is live. Normal deletion writes a
  tombstone by compare-and-swap so a delayed writer cannot recreate the same
  record lifetime. Loading a tombstone returns `{:error, :deleted}`.

  Agent Servers create revision zero before a new persistent activation reports
  ready. They store later `state_version` values as the record revision. Each
  successful Turn writes one new revision, including an identical-state result.
  A failure before commit leaves the stored revision unchanged. A failure in
  post-commit work does not undo the stored revision. Restore retains it.
  Direct `save_agent/3` calls use the revision supplied in their options.

  Caller execution context is not part of the checkpoint. Only values that
  application code puts in portable Agent or Plugin state can be stored.

  A Plugin Persistence facet can convert only its paired owned-state value in
  the default checkpoint path. Complete custom Agent checkpoints bypass this
  conversion and keep their opaque callback contract.

  Compatible operations without a namespace use the instance, Agent module,
  partition, and ID key with record format 2. Namespaced operations use the
  exact Agent Ref key with record format 3. If only a compatible key exists,
  the namespaced operation continues to use it. If both keys exist, the
  operation returns an identity collision. Jido does not rewrite data across
  the two keys automatically.
  """

  alias Jido.Agent
  alias Jido.Agent.Ref
  alias Jido.Error
  alias Jido.Persistence.{Checkpoint, Record}
  alias Jido.PortableTerm

  @key_prefix "jido:agent:v1:"
  @ref_key_prefix "jido:agent:v2:"

  @type adapter_config :: {module(), keyword()} | module() | nil | false

  @doc "Normalizes an adapter declaration."
  @spec normalize_adapter(adapter_config()) :: {module(), keyword()} | nil
  def normalize_adapter(nil), do: nil
  def normalize_adapter(false), do: nil

  def normalize_adapter({adapter, opts}) when is_atom(adapter) and is_list(opts) do
    if Keyword.keyword?(opts) do
      {adapter, opts}
    else
      raise ArgumentError, "persistence adapter options must be a keyword list"
    end
  end

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
  A failed check does not replace the stored record. A tombstone preserves the
  revision barrier after logical deletion. This check is not a writer lease.
  """
  @spec save_agent(adapter_config() | atom(), Agent.t(), keyword()) ::
          :ok | {:error, term()}
  def save_agent(source, agent, opts \\ [])

  def save_agent(source, %Agent{} = agent, opts) do
    protect(:compare_and_swap, fn ->
      with :ok <- validate_operation_options(opts),
           {:ok, {adapter, adapter_opts}, instance} <- resolve_source(source, opts),
           partition = Keyword.get(opts, :partition),
           {:ok, identity} <-
             storage_identity(
               adapter,
               adapter_opts,
               instance,
               agent.module,
               agent.id,
               partition,
               Keyword.get(opts, :namespace)
             ),
           {:ok, record} <- build_record(agent, instance, opts, identity),
           {:ok, expected_revision} <- expected_revision(opts),
           {:ok, expected_value} <-
             current_value(adapter, adapter_opts, record, identity, expected_revision),
           {:ok, value} <- Record.encode(record),
           :ok <-
             adapter_compare_and_swap(
               adapter,
               identity.key,
               expected_value,
               value,
               adapter_opts
             ) do
        :ok
      end
    end)
  end

  @doc false
  @spec create_agent(adapter_config() | atom(), Agent.t(), keyword()) ::
          :ok | {:error, term()}
  def create_agent(source, %Agent{} = agent, opts \\ []) do
    protect(:compare_and_swap, fn ->
      with :ok <- validate_operation_options(opts),
           {:ok, {adapter, adapter_opts}, instance} <- resolve_source(source, opts),
           :ok <- validate_initial_revision(opts),
           partition = Keyword.get(opts, :partition),
           {:ok, identity} <-
             storage_identity(
               adapter,
               adapter_opts,
               instance,
               agent.module,
               agent.id,
               partition,
               Keyword.get(opts, :namespace)
             ),
           {:ok, record} <-
             build_record(agent, instance, Keyword.put(opts, :revision, 0), identity),
           {:ok, value} <- Record.encode(record),
           :ok <-
             adapter_compare_and_swap(
               adapter,
               identity.key,
               :not_found,
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

  def load_agent(source, agent_module, agent_id, opts)
      when is_atom(agent_module) and is_binary(agent_id) do
    case load_agent_with_revision(source, agent_module, agent_id, opts) do
      {:ok, agent, _revision} -> {:ok, agent}
      {:error, _reason} = error -> error
    end
  end

  @doc false
  @spec load_agent_with_revision(adapter_config() | atom(), module(), String.t(), keyword()) ::
          {:ok, Agent.t(), non_neg_integer()} | {:error, term()}
  def load_agent_with_revision(source, agent_module, agent_id, opts \\ [])

  def load_agent_with_revision(source, agent_module, agent_id, opts)
      when is_atom(agent_module) and is_binary(agent_id) do
    protect(:get, fn ->
      with :ok <- validate_operation_options(opts),
           {:ok, {adapter, adapter_opts}, instance} <- resolve_source(source, opts),
           partition = Keyword.get(opts, :partition),
           {:ok, identity} <-
             storage_identity(
               adapter,
               adapter_opts,
               instance,
               agent_module,
               agent_id,
               partition,
               Keyword.get(opts, :namespace)
             ),
           {:ok, value} <- adapter_get(adapter, identity.key, adapter_opts),
           {:ok, record} <- Record.decode(value),
           :ok <- validate_record(record, identity, instance, agent_module, agent_id, partition),
           :ok <- require_active(record),
           :ok <- validate_definition_revision(record, agent_module),
           {:ok, checkpoint} <- restore_checkpoint(record, agent_module),
           {:ok, agent} <-
             Agent.restore(agent_module, checkpoint, restore_context(record, instance)),
           :ok <- validate_restored_identity(agent, agent_module, agent_id) do
        {:ok, agent, Record.revision(record)}
      end
    end)
  end

  @doc "Logically deletes one Agent record with a compare-and-swap tombstone."
  @spec delete_agent(adapter_config() | atom(), module(), String.t(), keyword()) ::
          :ok | {:error, term()}
  def delete_agent(source, agent_module, agent_id, opts \\ [])

  def delete_agent(source, agent_module, agent_id, opts)
      when is_atom(agent_module) and is_binary(agent_id) do
    protect(:delete, fn ->
      with :ok <- validate_operation_options(opts),
           {:ok, {adapter, adapter_opts}, instance} <- resolve_source(source, opts),
           partition = Keyword.get(opts, :partition),
           {:ok, identity} <-
             storage_identity(
               adapter,
               adapter_opts,
               instance,
               agent_module,
               agent_id,
               partition,
               Keyword.get(opts, :namespace)
             ) do
        delete_current(
          adapter,
          adapter_opts,
          identity,
          instance,
          agent_module,
          agent_id,
          partition
        )
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

  @doc false
  @spec agent_key(Ref.t()) :: binary()
  def agent_key(%Ref{} = ref) do
    ref = Ref.new!(ref)
    identity = :erlang.term_to_binary({ref.namespace, ref.partition, ref.id})
    @ref_key_prefix <> Base.url_encode64(identity, padding: false)
  end

  defp resolve_instance_config(jido) when is_atom(jido) and not is_nil(jido) do
    config =
      cond do
        live_instance?(jido) -> Jido.instance_persistence(jido)
        function_exported?(jido, :__jido_persistence__, 0) -> jido.__jido_persistence__()
        true -> nil
      end

    config
    |> normalize_adapter_result()
    |> validate_adapter_result()
  rescue
    error -> {:error, {:invalid_persistence_config, error}}
  end

  defp resolve_instance_config(_jido), do: {:ok, nil}

  defp resolve_source(source, opts) do
    {config_result, default_instance} =
      cond do
        is_atom(source) and not is_nil(source) and
            function_exported?(source, :__jido_persistence__, 0) ->
          {resolve_instance_config(source), source}

        live_instance?(source) ->
          {resolve_instance_config(source), source}

        true ->
          {resolve_config(source, nil), nil}
      end

    with {:ok, config} <- config_result,
         {:ok, config} <- require_adapter(config) do
      {:ok, config, Keyword.get(opts, :instance, default_instance)}
    end
  end

  defp live_instance?(source) when is_atom(source) and not is_nil(source) do
    is_pid(Process.whereis(source)) and
      is_pid(Process.whereis(Jido.runtime_store_name(source)))
  end

  defp live_instance?(_source), do: false

  defp require_adapter(nil), do: {:error, :persistence_not_configured}
  defp require_adapter(config), do: {:ok, config}

  defp normalize_adapter_result(config) do
    {:ok, normalize_adapter(config)}
  rescue
    error -> {:error, {:invalid_persistence_config, error}}
  end

  defp validate_adapter_result({:ok, nil}), do: {:ok, nil}

  defp validate_adapter_result({:ok, {adapter, opts} = config}) do
    with {:module, ^adapter} <- Code.ensure_loaded(adapter),
         true <- function_exported?(adapter, :get, 2),
         true <- function_exported?(adapter, :compare_and_swap, 4),
         :ok <- validate_adapter_options(adapter, opts) do
      {:ok, config}
    else
      {:error, _reason} = error -> error
      _value -> {:error, {:invalid_persistence_adapter, adapter}}
    end
  end

  defp validate_adapter_result({:error, _reason} = error), do: error

  defp validate_adapter_options(adapter, opts) do
    if function_exported?(adapter, :validate_options, 1) do
      case adapter.validate_options(opts) do
        :ok -> :ok
        {:error, reason} -> {:error, {:invalid_persistence_options, adapter, reason}}
        result -> {:error, {:invalid_persistence_options, adapter, {:invalid_result, result}}}
      end
    else
      :ok
    end
  rescue
    error -> {:error, {:invalid_persistence_options, adapter, {:error, error}}}
  catch
    kind, reason -> {:error, {:invalid_persistence_options, adapter, {kind, reason}}}
  end

  defp validate_operation_options(opts) do
    if Keyword.keyword?(opts), do: :ok, else: invalid_operation_options(opts)
  end

  defp invalid_operation_options(opts), do: {:error, {:invalid_persistence_options, opts}}

  defp expected_revision(opts) do
    case Keyword.fetch(opts, :expected_revision) do
      :error -> {:ok, :any}
      {:ok, revision} when is_integer(revision) and revision >= 0 -> {:ok, revision}
      {:ok, revision} -> {:error, {:invalid_expected_revision, revision}}
    end
  end

  defp validate_initial_revision(opts) do
    case Keyword.get(opts, :revision, 0) do
      0 -> :ok
      revision -> {:error, {:invalid_initial_revision, revision}}
    end
  end

  defp current_value(adapter, opts, record, identity, expected_revision) do
    case adapter_get(adapter, identity.key, opts) do
      {:error, :not_found} when expected_revision in [:any, 0] ->
        {:ok, :not_found}

      {:error, :not_found} ->
        {:error, :conflict}

      {:ok, value} ->
        with {:ok, current} <- Record.decode(value),
             :ok <- validate_record_against_record(current, record, identity),
             :ok <- require_active_for_write(current),
             :ok <- check_revision(current, record, expected_revision) do
          {:ok, value}
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp check_revision(current, record, expected_revision) do
    cond do
      expected_revision != :any and Record.revision(current) != expected_revision ->
        {:error, :conflict}

      Record.revision(record) > Record.revision(current) ->
        :ok

      record === current ->
        :ok

      true ->
        {:error, :conflict}
    end
  end

  defp build_record(agent, instance, opts, identity) do
    partition = Keyword.get(opts, :partition)
    revision = Keyword.get(opts, :revision, 0)
    reason = Keyword.get(opts, :reason, :manual)
    record_format = record_format(identity)

    context = %{
      instance: instance,
      partition: partition,
      revision: revision,
      reason: reason
    }

    with true <- is_integer(revision) and revision >= 0,
         {:ok, checkpoint} <- Checkpoint.dump(agent, context, record_format, reason),
         {:ok, record} <-
           build_active_record(agent, instance, partition, revision, checkpoint, identity) do
      {:ok, record}
    else
      false -> {:error, {:invalid_checkpoint, :shape}}
      {:error, _reason} = error -> error
    end
  end

  defp storage_identity(
         _adapter,
         _adapter_opts,
         instance,
         agent_module,
         agent_id,
         partition,
         nil
       ) do
    {:ok,
     %{
       mode: :legacy,
       key: agent_key(instance, agent_module, agent_id, partition)
     }}
  end

  defp storage_identity(
         adapter,
         adapter_opts,
         instance,
         agent_module,
         agent_id,
         partition,
         namespace
       ) do
    with {:ok, ref} <- Ref.new(namespace: namespace, partition: partition, id: agent_id) do
      ref_identity = %{mode: :ref, key: agent_key(ref), namespace: namespace}

      legacy_identity = %{
        mode: :legacy,
        key: agent_key(instance, agent_module, agent_id, partition)
      }

      select_storage_identity(adapter, adapter_opts, ref_identity, legacy_identity)
    end
  end

  defp select_storage_identity(adapter, opts, ref_identity, legacy_identity) do
    case {
      stored_key_state(adapter, ref_identity.key, opts),
      stored_key_state(adapter, legacy_identity.key, opts)
    } do
      {:missing, :missing} ->
        {:ok, ref_identity}

      {:present, :missing} ->
        {:ok, ref_identity}

      {:missing, :present} ->
        {:ok, legacy_identity}

      {:present, :present} ->
        {:error,
         {:persistence_identity_collision,
          %{ref_key: ref_identity.key, legacy_key: legacy_identity.key}}}

      {{:error, reason}, _legacy} ->
        {:error, reason}

      {_ref, {:error, reason}} ->
        {:error, reason}
    end
  end

  defp stored_key_state(adapter, key, opts) do
    case adapter_get(adapter, key, opts) do
      {:ok, _value} -> :present
      {:error, :not_found} -> :missing
      {:error, reason} -> {:error, reason}
    end
  end

  defp record_format(%{mode: :legacy}), do: Record.format_version()
  defp record_format(%{mode: :ref}), do: Record.ref_format_version()

  defp build_active_record(agent, instance, partition, revision, checkpoint, %{mode: :legacy}) do
    Record.build_active(agent, instance, partition, revision, checkpoint)
  end

  defp build_active_record(agent, _instance, partition, revision, checkpoint, %{
         mode: :ref,
         namespace: namespace
       }) do
    Record.build_ref_active(agent, namespace, partition, revision, checkpoint)
  end

  defp build_tombstone_record(
         instance,
         agent_module,
         agent_id,
         partition,
         revision,
         %{mode: :legacy}
       ) do
    Record.build_tombstone(instance, agent_module, agent_id, partition, revision)
  end

  defp build_tombstone_record(
         _instance,
         agent_module,
         agent_id,
         partition,
         revision,
         %{mode: :ref, namespace: namespace}
       ) do
    Record.build_ref_tombstone(namespace, agent_module, agent_id, partition, revision)
  end

  defp validate_record(record, %{mode: :legacy}, instance, agent_module, agent_id, partition) do
    Record.validate(record, instance, agent_module, agent_id, partition)
  end

  defp validate_record(
         record,
         %{mode: :ref, namespace: namespace},
         _instance,
         agent_module,
         agent_id,
         partition
       ) do
    Record.validate_ref(record, namespace, agent_module, agent_id, partition)
  end

  defp validate_record_against_record(current, record, %{mode: :legacy}) do
    Record.validate(
      current,
      record.instance,
      record.agent_module,
      record.agent_id,
      record.partition
    )
  end

  defp validate_record_against_record(current, record, %{
         mode: :ref,
         namespace: namespace
       }) do
    Record.validate_ref(
      current,
      namespace,
      record.agent_module,
      record.agent_id,
      record.partition
    )
  end

  defp delete_current(
         adapter,
         adapter_opts,
         identity,
         instance,
         agent_module,
         agent_id,
         partition
       ) do
    case adapter_get(adapter, identity.key, adapter_opts) do
      {:error, :not_found} ->
        with {:ok, tombstone} <-
               build_tombstone_record(
                 instance,
                 agent_module,
                 agent_id,
                 partition,
                 0,
                 identity
               ),
             {:ok, value} <- Record.encode(tombstone) do
          adapter_compare_and_swap(adapter, identity.key, :not_found, value, adapter_opts)
        end

      {:ok, expected_value} ->
        with {:ok, current} <- Record.decode(expected_value),
             :ok <-
               validate_record(current, identity, instance, agent_module, agent_id, partition) do
          case Record.kind(current) do
            :tombstone ->
              :ok

            :active ->
              with {:ok, tombstone} <-
                     build_tombstone_record(
                       instance,
                       agent_module,
                       agent_id,
                       partition,
                       Record.revision(current),
                       identity
                     ),
                   {:ok, value} <- Record.encode(tombstone) do
                adapter_compare_and_swap(
                  adapter,
                  identity.key,
                  expected_value,
                  value,
                  adapter_opts
                )
              end
          end
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp require_active(record) do
    case Record.kind(record) do
      :active -> :ok
      :tombstone -> {:error, :deleted}
      :unknown -> {:error, {:invalid_persistence_record, :kind}}
    end
  end

  defp require_active_for_write(record) do
    case Record.kind(record) do
      :active -> :ok
      :tombstone -> {:error, :conflict}
      :unknown -> {:error, {:invalid_persistence_record, :kind}}
    end
  end

  defp restore_checkpoint(record, agent_module) do
    checkpoint = Record.checkpoint(record)

    if Record.format(record) in [Record.format_version(), Record.ref_format_version()] do
      Checkpoint.load(agent_module, checkpoint, Record.format(record), :restore)
    else
      {:ok, checkpoint}
    end
  end

  defp validate_definition_revision(record, agent_module) do
    case Record.agent_vsn(record) do
      nil ->
        :ok

      saved_vsn ->
        case current_definition_revision(agent_module) do
          ^saved_vsn ->
            :ok

          current_vsn ->
            {:error,
             Error.validation_error("Stored Agent definition revision does not match",
               kind: :config,
               subject: agent_module,
               details: %{
                 code: :definition_mismatch,
                 saved_vsn: saved_vsn,
                 current_vsn: current_vsn
               }
             )}
        end
    end
  end

  defp current_definition_revision(agent_module) do
    if Code.ensure_loaded?(agent_module) and function_exported?(agent_module, :vsn, 0),
      do: agent_module.vsn(),
      else: nil
  end

  defp validate_restored_identity(%Agent{module: module, id: id}, module, id), do: :ok

  defp validate_restored_identity(_agent, _module, _id),
    do: {:error, {:invalid_persistence_record, :checkpoint_identity}}

  defp restore_context(record, instance) do
    %{
      instance: instance,
      partition: Map.fetch!(record, :partition),
      revision: Record.revision(record),
      reason: :restore
    }
  end

  defp adapter_get(adapter, key, opts) do
    case adapter.get(key, opts) do
      {:ok, value} when is_binary(value) -> {:ok, value}
      {:error, _reason} = error -> error
      result -> invalid_adapter_result(:get, result)
    end
  end

  defp adapter_compare_and_swap(adapter, key, expected, value, opts) do
    result =
      try do
        adapter.compare_and_swap(key, expected, value, opts)
      rescue
        error -> {:callback_fault, :error, error}
      catch
        kind, reason -> {:callback_fault, kind, reason}
      end

    case result do
      :ok ->
        :ok

      {:error, :conflict} = error ->
        error

      {:error, {:rejected, _reason}} = error ->
        error

      {:error, :indeterminate} = error ->
        error

      {:error, {:indeterminate, _reason}} = error ->
        error

      {:error, reason} ->
        {:error, {:indeterminate, reason}}

      {:callback_fault, kind, reason} ->
        {:error, {:indeterminate, persistence_failure_value(:compare_and_swap, kind, reason)}}

      invalid ->
        {:error, {:indeterminate, invalid_adapter_result_value(:compare_and_swap, invalid)}}
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
    {:error, invalid_adapter_result_value(operation, result)}
  end

  defp persistence_failure(operation, kind, reason) do
    {:error, persistence_failure_value(operation, kind, reason)}
  end

  defp invalid_adapter_result_value(operation, result) do
    Error.execution_error("Persistence adapter returned an invalid result",
      details: %{
        code: :persistence_invalid_callback_result,
        operation: operation,
        result: result
      }
    )
  end

  defp persistence_failure_value(operation, kind, reason) do
    Error.execution_error("Persistence adapter operation failed",
      details: %{
        code: :persistence_callback_failed,
        operation: operation,
        kind: kind,
        reason: reason
      }
    )
  end

  @doc false
  @spec portable_term?(term()) :: boolean()
  def portable_term?(term), do: PortableTerm.valid?(term)
end
