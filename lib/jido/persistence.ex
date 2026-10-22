defmodule Jido.Persistence do
  @moduledoc """
  Saves and restores portable Agent checkpoints through a persistence adapter.

  This module owns Agent record keys, encoding, and validation.
  `Jido.Persistence.Store` contains byte-adapter faults and write outcomes.
  Adapters only store binary keys and values.

  Durable values are versioned active records or compact tombstones. An active
  record does not prove that an Agent process is live. Normal deletion writes a
  tombstone by compare-and-swap so a delayed writer cannot recreate the same
  record lifetime. Loading a tombstone returns `{:error, :deleted}`.

  Agent Servers create revision zero before a new persistent activation reports
  ready. They store later `state_version` values as the record revision. Each
  successful ordinary Turn writes one new revision, including an identical-state result.
  With persistence enabled, each Flow Turn also saves acceptance before execution.
  Its optional `server_turn` envelope field belongs to AgentServer, outside Agent domain state.
  Completion saves the candidate Agent and terminal receipt in one write.
  Failed or cancelled durable Turns save a terminal receipt with unchanged state.
  An ordinary failure before commit leaves the stored revision unchanged. A failure in
  post-commit work does not undo the stored revision. Restore retains it.
  Direct `save_agent/3` calls use the revision supplied in their options.

  State and current topology are saved together under one `rev`. The record
  uses `fmt` for its storage format and `vsn` for saved Agent provenance.
  A topology-only change needs a new revision. Child Agent state is saved in
  separate records; this is not an atomic save of a whole Agent family.

  Caller execution context is not part of the Agent snapshot. A pending Flow
  saves its portable context in the Server Turn receipt. Live Agent state
  contains domain fields and Plugin-owned fields and must match its schema.
  Custom Agent or Plugin conversion runs before Jido checks the complete
  stored representation for portability. Restore checks the stored record
  before conversion, then validates the reconstructed live state and identity.

  A Plugin Persistence facet can convert only its paired owned-state value in
  the default checkpoint path. Complete custom Agent checkpoints bypass this
  conversion and keep their opaque callback contract.

  Each durable Agent uses one exact `{namespace, partition, id}` Ref key and
  record format 4. Supply `:namespace`, or use the namespace of a live Jido
  `:instance`. The Agent module is checked in the record, but is not part of
  its key. `:instance` also supplies checkpoint callback context.

  New writes use record format 4 with a complete snapshot format 1 payload.
  Earlier checkpoint payloads require explicit conversion before this version
  starts. The record reader retains format 3 keys for adapter cutover only.
  Restore does not rebuild a saved definition from the current source module.
  """

  alias Jido.Agent
  alias Jido.Agent.Ref
  alias Jido.Error
  alias Jido.Persistence.{AdapterOps, Checkpoint, Identity, Record, Source, Store}
  alias Jido.Telemetry.Persistence, as: PersistenceTelemetry
  alias Jido.PortableTerm

  @identity_options [:instance, :namespace, :partition]
  @create_options @identity_options ++ [:reason, :revision, :server_turn]
  @save_options @create_options ++ [:expected_revision]

  @typedoc "A direct persistence adapter declaration."
  @type adapter_config :: {module(), keyword()} | module() | nil | false

  @typedoc "A portable snapshot returned by `snapshot/2`."
  @type snapshot :: %{
          required(:format) => pos_integer(),
          required(:agent) => Agent.t(),
          required(:references) => %{module() => binary()},
          required(:state_format) => :default | :custom
        }

  @doc "Captures the complete Agent as portable data without writing storage."
  @spec snapshot(Agent.t(), keyword()) :: {:ok, snapshot()} | {:error, term()}
  def snapshot(agent, opts \\ []) do
    with {:ok, opts} <- Jido.Agent.Validation.options(opts, [:context]),
         :ok <- Jido.Agent.Data.plain_map(Map.get(opts, :context, %{})),
         do:
           Checkpoint.dump(
             agent,
             Map.get(opts, :context, %{}),
             Record.format_version(),
             :snapshot
           )
  end

  @doc "Restores saved definition and state without consulting the source definition."
  @spec restore(snapshot(), keyword()) :: {:ok, Agent.t()} | {:error, term()}
  def restore(snapshot, opts \\ []) do
    with {:ok, opts} <- Jido.Agent.Validation.options(opts, [:context]),
         :ok <- Jido.Agent.Data.plain_map(Map.get(opts, :context, %{})),
         do: Checkpoint.restore_snapshot(snapshot, Map.get(opts, :context, %{}))
  end

  @doc "Runs an explicit data upgrade Action before resolving saved code references."
  @spec upgrade(snapshot(), term(), keyword()) :: {:ok, Agent.t()} | {:error, term()}
  def upgrade(snapshot, action, opts \\ []) do
    with {:ok, opts} <- Jido.Agent.Validation.options(opts, [:context]),
         context = Map.get(opts, :context, %{}),
         :ok <- Jido.Agent.Data.plain_map(context),
         do:
           Jido.Persistence.Snapshot.upgrade(
             snapshot,
             action,
             context,
             &restore(&1, context: context)
           )
  end

  @doc false
  @spec normalize_adapter(adapter_config()) :: {module(), keyword()} | nil
  defdelegate normalize_adapter(config), to: Source

  @doc """
  Resolves and validates a persistence adapter configuration.

  Pass an adapter module or `{adapter, options}` for an explicit configuration.
  Pass `:inherit` with a Jido instance name to use that instance's configuration.
  A running instance's configuration takes priority over its module default.
  Pass `nil` or `false` to disable persistence. A disabled or unconfigured source
  returns `{:ok, nil}`.

  The result is a normalized `{adapter, options}` tuple or `nil`. This function
  checks required adapter callbacks and options. It does not start the adapter
  or confirm that its storage is durable or shared across nodes.
  """
  @spec resolve_config(:inherit | adapter_config(), atom() | nil) ::
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

  The public options are `:instance`, `:namespace`, `:partition`, `:reason`,
  `:revision`, and `:expected_revision`. `:server_turn` is reserved for the
  AgentServer durable record. Unknown and duplicate options return an error.
  """
  @spec save_agent(adapter_config() | atom(), Agent.t(), keyword()) ::
          :ok | {:error, term()}
  def save_agent(source, agent, opts \\ [])

  def save_agent(source, %Agent{} = agent, opts) do
    PersistenceTelemetry.observe(:compare_and_swap, source, agent.module, agent.id, opts, fn ->
      AdapterOps.protect(:compare_and_swap, fn ->
        with :ok <- Source.validate_operation_options(opts, @save_options),
             {:ok, {adapter, adapter_opts}, instance} <- Source.resolve(source, opts),
             {:ok, ref} <- Identity.resolve(instance, agent.id, opts),
             {:ok, record} <- build_record(agent, instance, opts, ref),
             {:ok, expected_revision} <- expected_revision(opts),
             {:ok, expected_value} <-
               current_value(adapter, adapter_opts, record, ref, expected_revision),
             {:ok, value} <- Record.encode(record),
             :ok <-
               Store.compare_and_swap(
                 {adapter, adapter_opts},
                 Identity.agent_key(ref),
                 expected_value,
                 value
               ) do
          :ok
        end
      end)
    end)
  end

  def save_agent(_source, agent, _opts),
    do: invalid_public_input(:save_agent, %{agent: agent})

  @doc false
  @spec create_agent(adapter_config() | atom(), Agent.t(), keyword()) ::
          :ok | {:error, term()}
  def create_agent(source, %Agent{} = agent, opts \\ []) do
    PersistenceTelemetry.observe(:compare_and_swap, source, agent.module, agent.id, opts, fn ->
      AdapterOps.protect(:compare_and_swap, fn ->
        with :ok <- Source.validate_operation_options(opts, @create_options),
             {:ok, {adapter, adapter_opts}, instance} <- Source.resolve(source, opts),
             :ok <- validate_initial_revision(opts),
             {:ok, ref} <- Identity.resolve(instance, agent.id, opts),
             {:ok, record} <-
               build_record(agent, instance, Keyword.put(opts, :revision, 0), ref),
             {:ok, value} <- Record.encode(record),
             :ok <-
               Store.compare_and_swap(
                 {adapter, adapter_opts},
                 Identity.agent_key(ref),
                 :not_found,
                 value
               ) do
          :ok
        end
      end)
    end)
  end

  @doc """
  Loads and restores one Agent value.

  Use `:instance`, `:namespace`, and `:partition` to select its durable identity.
  Unknown and duplicate options return an error.
  """
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

  @doc """
  Loads and restores one Agent value with its stored revision.

  Use the returned revision as `:expected_revision` for a later direct
  `save_agent/3` call. The namespace and partition options identify the same
  durable record as `load_agent/4`. The accepted options are `:instance`,
  `:namespace`, and `:partition`. Unknown and duplicate options return an error.
  """
  @spec load_agent_with_revision(adapter_config() | atom(), module(), String.t(), keyword()) ::
          {:ok, Agent.t(), non_neg_integer()} | {:error, term()}
  def load_agent_with_revision(source, agent_module, agent_id, opts \\ [])

  def load_agent_with_revision(source, agent_module, agent_id, opts)
      when is_atom(agent_module) and is_binary(agent_id) do
    case load_agent_with_server_turn(source, agent_module, agent_id, opts) do
      {:ok, agent, revision, _turn} -> {:ok, agent, revision}
      error -> error
    end
  end

  def load_agent_with_revision(_source, agent_module, agent_id, _opts),
    do:
      invalid_public_input(:load_agent_with_revision, %{
        agent_module: agent_module,
        agent_id: agent_id
      })

  @doc """
  Logically deletes one Agent record with a compare-and-swap tombstone.

  Use `:instance`, `:namespace`, and `:partition` to select its durable identity.
  Unknown and duplicate options return an error.
  """
  @spec delete_agent(adapter_config() | atom(), module(), String.t(), keyword()) ::
          :ok | {:error, term()}
  def delete_agent(source, agent_module, agent_id, opts \\ [])

  def delete_agent(source, agent_module, agent_id, opts)
      when is_atom(agent_module) and is_binary(agent_id) do
    PersistenceTelemetry.observe(:delete, source, agent_module, agent_id, opts, fn ->
      AdapterOps.protect(:delete, fn ->
        with :ok <- Source.validate_operation_options(opts, @identity_options),
             {:ok, {adapter, adapter_opts}, instance} <- Source.resolve(source, opts),
             {:ok, ref} <- Identity.resolve(instance, agent_id, opts) do
          delete_current(adapter, adapter_opts, ref, agent_module)
        end
      end)
    end)
  end

  def delete_agent(_source, agent_module, agent_id, _opts),
    do: invalid_public_input(:delete_agent, %{agent_module: agent_module, agent_id: agent_id})

  defp invalid_public_input(operation, details) do
    {:error,
     Error.validation_error("Persistence input is invalid",
       kind: :input,
       subject: __MODULE__,
       details: Map.put(details, :operation, operation)
     )}
  end

  @doc false
  @spec agent_key(Ref.t()) :: binary()
  def agent_key(%Ref{} = ref), do: Identity.agent_key(ref)

  @doc false
  def load_agent_with_server_turn(source, agent_module, agent_id, opts) do
    PersistenceTelemetry.observe(:load, source, agent_module, agent_id, opts, fn ->
      AdapterOps.protect(:get, fn ->
        with :ok <- Source.validate_operation_options(opts, @identity_options),
             {:ok, {adapter, adapter_opts}, instance} <- Source.resolve(source, opts),
             {:ok, ref} <- Identity.resolve(instance, agent_id, opts),
             {:ok, value, _condition} <-
               Store.read({adapter, adapter_opts}, Identity.agent_key(ref)),
             {:ok, record} <- decode_record(value, agent_module),
             :ok <- Record.validate(record, ref, agent_module),
             :ok <- Record.require_active(record),
             {:ok, agent} <- Checkpoint.restore_agent(record, agent_module, agent_id, instance) do
          {:ok, agent, Record.revision(record), Map.get(record, :server_turn)}
        end
      end)
    end)
  end

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

  defp current_value(adapter, opts, record, ref, expected_revision) do
    case Store.read({adapter, opts}, Identity.agent_key(ref)) do
      {:error, :not_found} when expected_revision in [:any, 0] ->
        {:ok, :not_found}

      {:error, :not_found} ->
        {:error, :conflict}

      {:ok, value, condition} ->
        with {:ok, current} <- decode_record(value, record.agent_module),
             :ok <- Record.validate(current, ref, record.agent_module),
             :ok <- Record.require_active_for_write(current),
             :ok <- check_revision(current, record, expected_revision) do
          {:ok, condition}
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

  defp build_record(agent, instance, opts, ref) do
    partition = Keyword.get(opts, :partition)
    revision = Keyword.get(opts, :revision, 0)
    reason = Keyword.get(opts, :reason, :manual)
    record_format = Record.format_version()

    context = %{
      instance: instance,
      partition: partition,
      revision: revision,
      reason: reason
    }

    with true <- is_integer(revision) and revision >= 0,
         {:ok, checkpoint} <- Checkpoint.dump(agent, context, record_format, reason),
         {:ok, record} <-
           Record.build_active(agent, ref, revision, checkpoint, Keyword.get(opts, :server_turn)) do
      {:ok, record}
    else
      false -> {:error, {:invalid_checkpoint, :shape}}
      {:error, _reason} = error -> error
    end
  end

  defp delete_current(adapter, adapter_opts, ref, agent_module) do
    case read_for_delete({adapter, adapter_opts}, Identity.agent_key(ref)) do
      {:error, :not_found} ->
        with {:ok, tombstone} <- Record.build_tombstone(ref, agent_module, 0),
             {:ok, value} <- Record.encode(tombstone) do
          Store.compare_and_swap(
            {adapter, adapter_opts},
            Identity.agent_key(ref),
            :not_found,
            value
          )
        end

      {:ok, expected_value, condition} ->
        with {:ok, current} <- decode_record(expected_value, agent_module),
             :ok <- Record.validate(current, ref, agent_module) do
          case Record.kind(current) do
            :tombstone ->
              :ok

            :active ->
              with {:ok, tombstone} <-
                     Record.build_tombstone(ref, agent_module, Record.revision(current)),
                   {:ok, value} <- Record.encode(tombstone) do
                Store.compare_and_swap(
                  {adapter, adapter_opts},
                  Identity.agent_key(ref),
                  condition,
                  value
                )
              end
          end
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp decode_record(value, agent_module) do
    # The caller module supplies domain atoms; Record loads trusted envelope fields.
    _ = Code.ensure_loaded?(agent_module)
    Record.decode(value)
  end

  defp read_for_delete(config, key) do
    case Store.read(config, key) do
      {:error,
       %Error.ExecutionError{details: %{code: :persistence_callback_failed} = details} = error} ->
        {:error, %{error | details: Map.put(details, :operation, :delete)}}

      result ->
        result
    end
  end

  @doc false
  @spec portable_term?(term()) :: boolean()
  def portable_term?(term), do: PortableTerm.valid?(term)
end
