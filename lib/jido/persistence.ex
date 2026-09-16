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
  application code puts in the portable complete Agent state can be stored.
  This map contains both domain fields and Plugin-owned fields.

  A Plugin Persistence facet can convert only its paired owned-state value in
  the default checkpoint path. Complete custom Agent checkpoints bypass this
  conversion and keep their opaque callback contract.

  Compatible operations without a namespace use the instance, Agent module,
  partition, and ID key with record format 2. Namespaced operations use the
  exact Agent Ref key with record format 3. If only a compatible key exists,
  the namespaced operation continues to use it. If both keys exist, the
  operation returns an identity collision. Jido does not rewrite data across
  the two keys automatically. During a controlled migration, one
  `WriteAuthority` value routes both caller modes to the selected record key.
  """

  alias Jido.Agent
  alias Jido.Agent.Ref
  alias Jido.Error
  alias Jido.Persistence.{AdapterOps, Checkpoint, Identity, Record, Source, WriteAuthority}
  alias Jido.Telemetry.Persistence, as: PersistenceTelemetry
  alias Jido.PortableTerm

  @type adapter_config :: {module(), keyword()} | module() | nil | false

  @doc "Normalizes an adapter declaration."
  @spec normalize_adapter(adapter_config()) :: {module(), keyword()} | nil
  defdelegate normalize_adapter(config), to: Source

  @doc false
  @spec resolve_config(term(), atom() | nil) ::
          {:ok, {module(), keyword()} | nil} | {:error, term()}
  defdelegate resolve_config(config, jido), to: Source

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
    PersistenceTelemetry.observe(:compare_and_swap, source, agent.module, agent.id, opts, fn ->
      AdapterOps.protect(:compare_and_swap, fn ->
        with :ok <- Source.validate_operation_options(opts),
             {:ok, {adapter, adapter_opts}, instance} <- Source.resolve(source, opts),
             {:ok, identity} <-
               Identity.resolve({adapter, adapter_opts}, instance, agent.module, agent.id, opts),
             {:ok, record} <- build_record(agent, instance, opts, identity),
             {:ok, expected_revision} <- expected_revision(opts),
             {:ok, expected_value} <-
               current_value(adapter, adapter_opts, record, identity, expected_revision),
             {:ok, value} <- Record.encode(record),
             :ok <-
               AdapterOps.compare_and_swap(
                 adapter,
                 identity.key,
                 expected_value,
                 value,
                 adapter_opts
               ) do
          :ok
        end
      end)
    end)
  end

  def save_agent(_source, agent, _opts),
    do: invalid_public_input(:save_agent, %{agent: agent})

  @doc false
  @spec replace_agent(adapter_config() | atom(), Agent.t(), Agent.t(), keyword()) ::
          :ok | {:error, term()}
  def replace_agent(source, %Agent{} = current_agent, %Agent{} = target_agent, opts \\ []) do
    PersistenceTelemetry.observe(
      :compare_and_swap,
      source,
      target_agent.module,
      target_agent.id,
      opts,
      fn ->
        AdapterOps.protect(:compare_and_swap, fn ->
          with :ok <- Source.validate_operation_options(opts),
               :ok <- validate_replacement_agents(current_agent, target_agent),
               {:ok, {adapter, adapter_opts}, instance} <- Source.resolve(source, opts),
               partition = Keyword.get(opts, :partition),
               namespace when is_binary(namespace) <- Keyword.get(opts, :namespace),
               {:ok, %{mode: :ref} = identity} <-
                 Identity.resolve(
                   {adapter, adapter_opts},
                   instance,
                   current_agent.module,
                   current_agent.id,
                   opts
                 ),
               {:ok, record} <- build_record(target_agent, instance, opts, identity),
               {:ok, expected_revision} <- expected_revision(opts),
               {:ok, expected_value} <-
                 current_replacement_value(
                   adapter,
                   adapter_opts,
                   current_agent,
                   record,
                   identity,
                   expected_revision,
                   instance,
                   partition
                 ),
               {:ok, value} <- Record.encode(record),
               :ok <-
                 AdapterOps.compare_and_swap(
                   adapter,
                   identity.key,
                   expected_value,
                   value,
                   adapter_opts
                 ) do
            :ok
          else
            nil -> {:error, :stable_namespace_required}
            {:ok, %{mode: :legacy}} -> {:error, :stable_namespace_required}
            {:error, _reason} = error -> error
          end
        end)
      end
    )
  end

  @doc false
  @spec create_agent(adapter_config() | atom(), Agent.t(), keyword()) ::
          :ok | {:error, term()}
  def create_agent(source, %Agent{} = agent, opts \\ []) do
    PersistenceTelemetry.observe(:compare_and_swap, source, agent.module, agent.id, opts, fn ->
      AdapterOps.protect(:compare_and_swap, fn ->
        with :ok <- Source.validate_operation_options(opts),
             {:ok, {adapter, adapter_opts}, instance} <- Source.resolve(source, opts),
             :ok <- validate_initial_revision(opts),
             {:ok, identity} <-
               Identity.resolve({adapter, adapter_opts}, instance, agent.module, agent.id, opts),
             {:ok, record} <-
               build_record(agent, instance, Keyword.put(opts, :revision, 0), identity),
             {:ok, value} <- Record.encode(record),
             :ok <-
               AdapterOps.compare_and_swap(
                 adapter,
                 identity.key,
                 :not_found,
                 value,
                 adapter_opts
               ) do
          :ok
        end
      end)
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

  def load_agent(_source, agent_module, agent_id, _opts),
    do: invalid_public_input(:load_agent, %{agent_module: agent_module, agent_id: agent_id})

  @doc false
  @spec load_agent_with_revision(adapter_config() | atom(), module(), String.t(), keyword()) ::
          {:ok, Agent.t(), non_neg_integer()} | {:error, term()}
  def load_agent_with_revision(source, agent_module, agent_id, opts \\ [])

  def load_agent_with_revision(source, agent_module, agent_id, opts)
      when is_atom(agent_module) and is_binary(agent_id) do
    PersistenceTelemetry.observe(:load, source, agent_module, agent_id, opts, fn ->
      AdapterOps.protect(:get, fn ->
        with :ok <- Source.validate_operation_options(opts),
             {:ok, {adapter, adapter_opts}, instance} <- Source.resolve(source, opts),
             partition = Keyword.get(opts, :partition),
             {:ok, identity} <-
               Identity.resolve({adapter, adapter_opts}, instance, agent_module, agent_id, opts),
             {:ok, value, _condition} <- AdapterOps.get(adapter, identity.key, adapter_opts),
             {:ok, record} <- Record.decode(value),
             :ok <-
               Record.validate_for_identity(
                 record,
                 identity,
                 instance,
                 agent_module,
                 agent_id,
                 partition
               ),
             :ok <- Record.require_active(record),
             {:ok, agent} <- Checkpoint.restore_agent(record, agent_module, agent_id, instance) do
          {:ok, agent, Record.revision(record)}
        end
      end)
    end)
  end

  def load_agent_with_revision(_source, agent_module, agent_id, _opts),
    do:
      invalid_public_input(:load_agent_with_revision, %{
        agent_module: agent_module,
        agent_id: agent_id
      })

  @doc "Logically deletes one Agent record with a compare-and-swap tombstone."
  @spec delete_agent(adapter_config() | atom(), module(), String.t(), keyword()) ::
          :ok | {:error, term()}
  def delete_agent(source, agent_module, agent_id, opts \\ [])

  def delete_agent(source, agent_module, agent_id, opts)
      when is_atom(agent_module) and is_binary(agent_id) do
    PersistenceTelemetry.observe(:delete, source, agent_module, agent_id, opts, fn ->
      AdapterOps.protect(:delete, fn ->
        with :ok <- Source.validate_operation_options(opts),
             {:ok, {adapter, adapter_opts}, instance} <- Source.resolve(source, opts),
             partition = Keyword.get(opts, :partition),
             {:ok, identity} <-
               Identity.resolve({adapter, adapter_opts}, instance, agent_module, agent_id, opts) do
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
    end)
  end

  def delete_agent(_source, agent_module, agent_id, _opts),
    do: invalid_public_input(:delete_agent, %{agent_module: agent_module, agent_id: agent_id})

  @doc """
  Creates an explicit write gate for a compatible-to-Ref identity migration.

  Stop old writers before this call. Supply the target `:namespace` and the
  same `:instance` and `:partition` that the writers use. The call rejects two
  existing records. It selects the existing record key, or the Ref key when no
  record exists. It does not write, move, or delete adapter data.

  Pass the returned value as `:write_authority` to every compatible and Ref
  read or write during the migration. These calls then use one record key and
  one compare-and-swap authority.
  """
  @spec establish_write_authority(adapter_config() | atom(), module(), String.t(), keyword()) ::
          {:ok, WriteAuthority.t()} | {:error, term()}
  def establish_write_authority(source, agent_module, agent_id, opts)
      when is_atom(agent_module) and is_binary(agent_id),
      do: Identity.establish_write_authority(source, agent_module, agent_id, opts)

  def establish_write_authority(_source, agent_module, agent_id, _opts),
    do:
      invalid_public_input(:establish_write_authority, %{
        agent_module: agent_module,
        agent_id: agent_id
      })

  defp invalid_public_input(operation, details) do
    {:error,
     Error.validation_error("Persistence input is invalid",
       kind: :input,
       subject: __MODULE__,
       details: Map.put(details, :operation, operation)
     )}
  end

  @doc false
  @spec agent_key(atom() | nil, module(), String.t(), term()) :: binary()
  def agent_key(instance, agent_module, agent_id, partition \\ nil)
      when (is_atom(instance) or is_nil(instance)) and is_atom(agent_module) and
             is_binary(agent_id),
      do: Identity.agent_key(instance, agent_module, agent_id, partition)

  @doc false
  @spec agent_key(Ref.t()) :: binary()
  def agent_key(%Ref{} = ref), do: Identity.agent_key(ref)

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
    case AdapterOps.get(adapter, identity.key, opts) do
      {:error, :not_found} when expected_revision in [:any, 0] ->
        {:ok, :not_found}

      {:error, :not_found} ->
        {:error, :conflict}

      {:ok, value, condition} ->
        with {:ok, current} <- Record.decode(value),
             :ok <- Record.validate_against_record(current, record, identity),
             :ok <- Record.require_active_for_write(current),
             :ok <- check_revision(current, record, expected_revision) do
          {:ok, condition}
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp current_replacement_value(
         adapter,
         opts,
         current_agent,
         target_record,
         %{mode: :ref, namespace: namespace} = identity,
         expected_revision,
         _instance,
         partition
       ) do
    case AdapterOps.get(adapter, identity.key, opts) do
      {:ok, value, condition} ->
        with {:ok, current_record} <- Record.decode(value),
             :ok <-
               Record.validate_ref(
                 current_record,
                 namespace,
                 current_agent.module,
                 current_agent.id,
                 partition
               ),
             :ok <- Record.require_active_for_write(current_record),
             :ok <- check_revision(current_record, target_record, expected_revision) do
          {:ok, condition}
        end

      {:error, :not_found} ->
        {:error, :conflict}

      {:error, _reason} = error ->
        error
    end
  end

  defp validate_replacement_agents(
         %Agent{id: id} = current_agent,
         %Agent{id: id} = target_agent
       )
       when is_binary(id) do
    with {:ok, _current} <- Agent.validate_instance(current_agent),
         {:ok, _target} <- Agent.validate_instance(target_agent),
         do: :ok
  end

  defp validate_replacement_agents(_current_agent, _target_agent),
    do: {:error, :agent_identity_mismatch}

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
    record_format = Record.format_for_identity(identity)

    context = %{
      instance: instance,
      partition: partition,
      revision: revision,
      reason: reason
    }

    with true <- is_integer(revision) and revision >= 0,
         {:ok, checkpoint} <- Checkpoint.dump(agent, context, record_format, reason),
         {:ok, record} <-
           Record.build_active_for_identity(
             agent,
             instance,
             partition,
             revision,
             checkpoint,
             identity
           ) do
      {:ok, record}
    else
      false -> {:error, {:invalid_checkpoint, :shape}}
      {:error, _reason} = error -> error
    end
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
    case AdapterOps.get(adapter, identity.key, adapter_opts) do
      {:error, :not_found} ->
        with {:ok, tombstone} <-
               Record.build_tombstone_for_identity(
                 instance,
                 agent_module,
                 agent_id,
                 partition,
                 0,
                 identity
               ),
             {:ok, value} <- Record.encode(tombstone) do
          AdapterOps.compare_and_swap(adapter, identity.key, :not_found, value, adapter_opts)
        end

      {:ok, expected_value, condition} ->
        with {:ok, current} <- Record.decode(expected_value),
             :ok <-
               Record.validate_for_identity(
                 current,
                 identity,
                 instance,
                 agent_module,
                 agent_id,
                 partition
               ) do
          case Record.kind(current) do
            :tombstone ->
              :ok

            :active ->
              with {:ok, tombstone} <-
                     Record.build_tombstone_for_identity(
                       instance,
                       agent_module,
                       agent_id,
                       partition,
                       Record.revision(current),
                       identity
                     ),
                   {:ok, value} <- Record.encode(tombstone) do
                AdapterOps.compare_and_swap(
                  adapter,
                  identity.key,
                  condition,
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

  @doc false
  @spec portable_term?(term()) :: boolean()
  def portable_term?(term), do: PortableTerm.valid?(term)
end
