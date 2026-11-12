defmodule Jido.Persistence do
  @moduledoc """
  Saves and restores portable Agent checkpoints through a persistence adapter.

  This module owns durable Agent operations and Ref resolution.
  `Jido.Persistence.Record` owns record keys, encoding, and validation.
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
  record format 1. Supply `:namespace`, or use the namespace of a live Jido
  `:instance`. The Agent module is checked in the record, but is not part of
  its key. `:instance` also supplies checkpoint callback context.

  Reads and writes use record format 1 with a complete snapshot format 1
  payload. Earlier record and snapshot shapes require conversion outside Jido
  before this version starts.
  Restore does not rebuild a saved definition from the current source module.
  """

  alias Jido.Agent
  alias Jido.Agent.Ref
  alias Jido.Error
  alias Jido.Persistence.{Checkpoint, Record, Store}
  alias Jido.Telemetry.Persistence, as: PersistenceTelemetry
  alias Jido.Codec.Term

  @identity_options [:instance, :namespace, :partition]
  @create_options @identity_options ++ [:agent_revision, :reason, :revision, :server_turn]
  @save_options @create_options ++ [:expected_revision]
  @upgrade_options @identity_options ++ [:context]
  @operation_options [
    :agent_revision,
    :expected_revision,
    :instance,
    :namespace,
    :partition,
    :reason,
    :revision,
    :server_turn
  ]

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
    with {:ok, opts} <- Jido.Agent.Schema.options(opts, [:context]),
         :ok <- Jido.Agent.Schema.plain_map(Map.get(opts, :context, %{})),
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
    with {:ok, opts} <- Jido.Agent.Schema.options(opts, [:context]),
         :ok <- Jido.Agent.Schema.plain_map(Map.get(opts, :context, %{})),
         do: Checkpoint.restore_snapshot(snapshot, Map.get(opts, :context, %{}))
  end

  @doc "Runs an explicit data upgrade Action before resolving saved code references."
  @spec upgrade(snapshot(), term(), keyword()) :: {:ok, Agent.t()} | {:error, term()}
  def upgrade(snapshot, action, opts \\ []) do
    with {:ok, opts} <- Jido.Agent.Schema.options(opts, [:context]),
         context = Map.get(opts, :context, %{}),
         :ok <- Jido.Agent.Schema.plain_map(context),
         do:
           Jido.Persistence.Snapshot.upgrade(
             snapshot,
             action,
             context,
             &restore(&1, context: context)
           )
  end

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
  def resolve_config(:inherit, jido), do: resolve_instance_config(jido)
  def resolve_config(nil, _jido), do: {:ok, nil}

  def resolve_config(config, _jido) do
    config
    |> normalize_adapter_result()
    |> validate_adapter_result()
  end

  @doc false
  def resolve_source(source, opts) do
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

  @doc false
  @spec validate_operation_options(term(), [atom()]) :: :ok | {:error, term()}
  def validate_operation_options(opts, allowed \\ @operation_options) do
    cond do
      not Keyword.keyword?(opts) ->
        {:error, {:invalid_persistence_options, opts}}

      Keyword.has_key?(opts, :write_authority) ->
        {:error, {:unsupported_persistence_option, :write_authority}}

      true ->
        validate_option_keys(Keyword.keys(opts), allowed)
    end
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

  The public options are `:instance`, `:namespace`, `:partition`, `:reason`,
  `:revision`, and `:expected_revision`. `:server_turn` is reserved for the
  AgentServer durable record. Unknown and duplicate options return an error.
  """
  @spec save_agent(adapter_config() | atom(), Agent.t(), keyword()) ::
          :ok | {:error, term()}
  def save_agent(source, agent, opts \\ [])

  def save_agent(source, %Agent{} = agent, opts) do
    with :ok <- validate_operation_options(opts, @save_options),
         do: save_record(source, agent, agent.module, opts)
  end

  def save_agent(_source, agent, _opts),
    do: invalid_public_input(:save_agent, %{agent: agent})

  @doc false
  def replace_agent(source, %Agent{} = agent, previous_module, opts)
      when is_atom(previous_module) do
    with :ok <- validate_operation_options(opts, @save_options),
         do: save_record(source, agent, previous_module, opts)
  end

  defp save_record(source, agent, previous_module, opts) do
    PersistenceTelemetry.observe(:compare_and_swap, source, agent.module, agent.id, opts, fn ->
      Store.protect(:compare_and_swap, fn ->
        with {:ok, {adapter, adapter_opts}, instance} <- resolve_source(source, opts),
             {:ok, ref} <- resolve_ref(instance, agent.id, opts),
             {:ok, record} <- build_record(agent, instance, opts, ref),
             {:ok, expected_revision} <- expected_revision(opts),
             {:ok, expected_value} <-
               current_value(
                 adapter,
                 adapter_opts,
                 record,
                 ref,
                 expected_revision,
                 previous_module
               ),
             {:ok, value} <- Record.encode(record),
             :ok <-
               Store.compare_and_swap(
                 {adapter, adapter_opts},
                 Record.agent_key(ref),
                 expected_value,
                 value
               ) do
          :ok
        end
      end)
    end)
  end

  @doc false
  @spec create_agent(adapter_config() | atom(), Agent.t(), keyword()) ::
          :ok | {:error, term()}
  def create_agent(source, %Agent{} = agent, opts \\ []) do
    PersistenceTelemetry.observe(:compare_and_swap, source, agent.module, agent.id, opts, fn ->
      Store.protect(:compare_and_swap, fn ->
        with :ok <- validate_operation_options(opts, @create_options),
             {:ok, {adapter, adapter_opts}, instance} <- resolve_source(source, opts),
             :ok <- validate_initial_revision(opts),
             {:ok, ref} <- resolve_ref(instance, agent.id, opts),
             {:ok, record} <-
               build_record(agent, instance, Keyword.put(opts, :revision, 0), ref),
             {:ok, value} <- Record.encode(record),
             :ok <-
               Store.compare_and_swap(
                 {adapter, adapter_opts},
                 Record.agent_key(ref),
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
      {:ok, agent, revision, _agent_revision, _turn} -> {:ok, agent, revision}
      error -> error
    end
  end

  def load_agent_with_revision(_source, agent_module, agent_id, _opts),
    do:
      invalid_public_input(:load_agent_with_revision, %{
        agent_module: agent_module,
        agent_id: agent_id
      })

  @doc false
  @spec load_agent_ref(adapter_config() | atom(), Ref.t(), keyword()) ::
          {:ok, Agent.t(), non_neg_integer(), non_neg_integer(), map() | nil}
          | {:error, term()}
  def load_agent_ref(source, ref, opts \\ [])

  def load_agent_ref(source, %Ref{} = ref, opts) do
    Store.protect(:get, fn ->
      with :ok <- validate_operation_options(opts, [:instance]),
           {:ok, {adapter, adapter_opts}, instance} <- resolve_source(source, opts),
           :ok <- validate_ref_instance(ref, instance),
           {:ok, value, _condition} <-
             Store.read({adapter, adapter_opts}, Record.agent_key(ref)),
           {:ok, record} <- Record.decode(value),
           {:ok, agent_module} <- record_agent_module(record),
           :ok <- Record.validate(record, ref, agent_module),
           :ok <- Record.require_active(record),
           {:ok, agent} <- Checkpoint.restore_agent(record, agent_module, ref.id, instance) do
        {:ok, agent, Record.revision(record), Record.agent_revision(record), Map.get(record, :server_turn)}
      end
    end)
  end

  def load_agent_ref(_source, ref, _opts),
    do: invalid_public_input(:load_agent_ref, %{agent_ref: ref})

  @doc """
  Atomically upgrades one inactive saved Agent.

  The upgrade Action receives the saved snapshot before old code references
  are resolved. A successful upgrade writes the next revision with
  compare-and-swap. An active durable Turn returns `{:error, :turn_in_flight}`.

  Use `:instance`, `:namespace`, and `:partition` to select durable identity.
  Use `:context` to pass Action context. Jido adds the durable identity,
  current revision, and `:stored_upgrade` reason to that context.
  """
  @spec upgrade_agent(adapter_config() | atom(), module(), String.t(), term(), keyword()) ::
          {:ok, Agent.t(), non_neg_integer()} | {:error, term()}
  def upgrade_agent(source, agent_module, agent_id, action, opts \\ [])

  def upgrade_agent(source, agent_module, agent_id, action, opts)
      when is_atom(agent_module) and is_binary(agent_id) do
    telemetry_opts =
      if Keyword.keyword?(opts), do: Keyword.put(opts, :reason, :stored_upgrade), else: opts

    PersistenceTelemetry.observe(
      :compare_and_swap,
      source,
      agent_module,
      agent_id,
      telemetry_opts,
      fn ->
        Store.protect(:compare_and_swap, fn ->
          with :ok <- validate_operation_options(opts, @upgrade_options),
               context = Keyword.get(opts, :context, %{}),
               :ok <- Jido.Agent.Schema.plain_map(context),
               {:ok, {adapter, adapter_opts}, instance} <- resolve_source(source, opts),
               {:ok, ref} <- resolve_ref(instance, agent_id, opts),
               key = Record.agent_key(ref),
               {:ok, value, condition} <- Store.read({adapter, adapter_opts}, key),
               {:ok, record} <- decode_record(value, agent_module),
               :ok <- Record.validate(record, ref, agent_module),
               :ok <- Record.require_active(record),
               :ok <- require_inactive_turn(record),
               revision = Record.revision(record),
               action_context = stored_upgrade_context(context, instance, ref, revision),
               {:ok, upgraded} <-
                 upgrade(Record.checkpoint(record), action, context: action_context),
               :ok <- validate_definition_upgrade(record, upgraded),
               next_revision = revision + 1,
               next_agent_revision = Record.agent_revision(record) + 1,
               {:ok, next_record} <-
                 build_record(
                   upgraded,
                   instance,
                   [
                     partition: ref.partition,
                     revision: next_revision,
                     agent_revision: next_agent_revision,
                     reason: :stored_upgrade,
                     server_turn: Map.get(record, :server_turn)
                   ],
                   ref
                 ),
               {:ok, next_value} <- Record.encode(next_record),
               :ok <-
                 Store.compare_and_swap(
                   {adapter, adapter_opts},
                   key,
                   condition,
                   next_value
                 ) do
            {:ok, upgraded, next_revision}
          end
        end)
      end
    )
  end

  def upgrade_agent(_source, agent_module, agent_id, _action, _opts),
    do:
      invalid_public_input(:upgrade_agent, %{
        agent_module: agent_module,
        agent_id: agent_id
      })

  defp validate_definition_upgrade(record, %Agent{vsn: next_vsn}) do
    if is_integer(next_vsn) and next_vsn > Record.agent_vsn(record),
      do: :ok,
      else: {:error, :definition_version_not_advanced}
  end

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
      Store.protect(:delete, fn ->
        with :ok <- validate_operation_options(opts, @identity_options),
             {:ok, {adapter, adapter_opts}, instance} <- resolve_source(source, opts),
             {:ok, ref} <- resolve_ref(instance, agent_id, opts) do
          delete_current(adapter, adapter_opts, ref, agent_module)
        end
      end)
    end)
  end

  def delete_agent(_source, agent_module, agent_id, _opts),
    do: invalid_public_input(:delete_agent, %{agent_module: agent_module, agent_id: agent_id})

  @doc false
  @spec delete_agent_ref(adapter_config() | atom(), Ref.t(), keyword()) :: :ok | {:error, term()}
  def delete_agent_ref(source, ref, opts \\ [])

  def delete_agent_ref(source, %Ref{} = ref, opts) do
    Store.protect(:compare_and_swap, fn ->
      with :ok <- validate_operation_options(opts, [:instance]),
           {:ok, {adapter, adapter_opts}, instance} <- resolve_source(source, opts),
           :ok <- validate_ref_instance(ref, instance),
           {:ok, value, _condition} <- Store.read({adapter, adapter_opts}, Record.agent_key(ref)),
           {:ok, record} <- Record.decode(value),
           {:ok, agent_module} <- record_agent_module(record) do
        delete_current(adapter, adapter_opts, ref, agent_module)
      end
    end)
  end

  def delete_agent_ref(_source, ref, _opts),
    do: invalid_public_input(:delete_agent_ref, %{agent_ref: ref})

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
  def agent_key(%Ref{} = ref), do: Record.agent_key(ref)

  defp resolve_ref(instance, agent_id, opts) do
    case Keyword.get_lazy(opts, :namespace, fn ->
           Jido.Instance.NamespaceRegistry.namespace(instance)
         end) do
      nil ->
        {:error, :stable_namespace_required}

      namespace ->
        Ref.new(namespace: namespace, partition: Keyword.get(opts, :partition), id: agent_id)
    end
  end

  defp validate_ref_instance(_ref, nil), do: :ok

  defp validate_ref_instance(ref, instance) do
    case Jido.Instance.NamespaceRegistry.namespace(instance) do
      namespace when is_binary(namespace) ->
        case Ref.validate_namespace(ref, namespace) do
          {:ok, _ref} -> :ok
          {:error, _reason} = error -> error
        end

      nil ->
        {:error, :stable_namespace_required}
    end
  end

  defp record_agent_module(%{agent_module: module})
       when is_atom(module) and not is_nil(module) do
    if Code.ensure_loaded?(module),
      do: {:ok, module},
      else: {:error, {:agent_module_unavailable, module}}
  end

  defp record_agent_module(_record), do: {:error, :invalid_persistence_record}

  @doc false
  def load_agent_with_server_turn(source, agent_module, agent_id, opts),
    do: observed_load(source, agent_module, agent_id, opts, opts)

  # An activation reports :reason on its load. Public load options do not accept it.
  defp open_load(source, agent, opts) do
    observed_load(source, agent.module, agent.id, Keyword.delete(opts, :reason), opts)
  end

  defp observed_load(source, agent_module, agent_id, opts, telemetry_opts) do
    PersistenceTelemetry.observe(:load, source, agent_module, agent_id, telemetry_opts, fn ->
      Store.protect(:get, fn ->
        with :ok <- validate_operation_options(opts, @identity_options),
             {:ok, {adapter, adapter_opts}, instance} <- resolve_source(source, opts),
             {:ok, ref} <- resolve_ref(instance, agent_id, opts),
             {:ok, value, _condition} <-
               Store.read({adapter, adapter_opts}, Record.agent_key(ref)),
             {:ok, record} <- decode_record(value, agent_module),
             :ok <- Record.validate(record, ref, agent_module),
             :ok <- Record.require_active(record),
             {:ok, agent} <- Checkpoint.restore_agent(record, agent_module, agent_id, instance) do
          {:ok, agent, Record.revision(record), Record.agent_revision(record), Map.get(record, :server_turn)}
        end
      end)
    end)
  end

  @doc false
  def open_agent(source, %Agent{} = agent, :create, opts) do
    with {:ok, _members} <-
           Jido.Agent.Topology.bind(agent, agent.state, &Jido.Agent.Validation.resolve/2),
         {:ok, agent} <-
           Jido.Agent.Topology.identify(nil, agent, &Jido.Agent.Validation.resolve/2),
         :ok <- create_agent(source, agent, opts),
         do: {:ok, agent, 0, 0, nil}
  end

  def open_agent(source, %Agent{} = agent, :restore, opts),
    do: open_load(source, agent, opts)

  defp require_inactive_turn(record) do
    case Map.get(record, :server_turn) do
      nil -> :ok
      %{status: status} when status in [:completed, :failed, :cancelled] -> :ok
      _turn -> {:error, :turn_in_flight}
    end
  end

  defp stored_upgrade_context(context, instance, ref, revision) do
    Map.merge(context, %{
      instance: instance,
      namespace: ref.namespace,
      partition: ref.partition,
      revision: revision,
      reason: :stored_upgrade
    })
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

  defp current_value(adapter, opts, record, ref, expected_revision, current_module) do
    case Store.read({adapter, opts}, Record.agent_key(ref)) do
      {:error, :not_found} when expected_revision in [:any, 0] ->
        {:ok, :not_found}

      {:error, :not_found} ->
        {:error, :conflict}

      {:ok, value, condition} ->
        with {:ok, current} <- decode_record(value, current_module),
             :ok <- Record.validate(current, ref, current_module),
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

  defp validate_option_keys(keys, allowed) do
    duplicate_keys = keys |> Enum.frequencies() |> duplicate_keys(keys)
    unsupported_keys = keys |> Enum.reject(&(&1 in allowed)) |> Enum.uniq()

    cond do
      duplicate_keys != [] ->
        {:error, {:invalid_persistence_options, {:duplicate_options, duplicate_keys}}}

      unsupported_keys != [] ->
        {:error, {:unsupported_persistence_options, unsupported_keys}}

      true ->
        :ok
    end
  end

  defp duplicate_keys(frequencies, keys) do
    keys
    |> Enum.filter(&(Map.fetch!(frequencies, &1) > 1))
    |> Enum.uniq()
  end

  defp resolve_instance_config(jido) do
    config =
      cond do
        live_instance?(jido) ->
          Jido.Instance.RuntimeStore.instance_persistence(jido)

        is_atom(jido) and function_exported?(jido, :__jido_persistence__, 0) ->
          jido.__jido_persistence__()

        true ->
          nil
      end

    config
    |> normalize_adapter_result()
    |> validate_adapter_result()
  rescue
    error -> {:error, {:invalid_persistence_config, error}}
  end

  defp live_instance?(source) when is_atom(source) and not is_nil(source) do
    is_pid(Process.whereis(source)) and
      is_pid(Process.whereis(Jido.Instance.Names.runtime_store(source)))
  end

  defp live_instance?(_source), do: false

  defp require_adapter(nil), do: {:error, :persistence_not_configured}
  defp require_adapter(config), do: {:ok, config}

  defp normalize_adapter_result(config) do
    {:ok, Store.normalize_adapter(config)}
  rescue
    error -> {:error, {:invalid_persistence_config, error}}
  end

  defp validate_adapter_result({:ok, nil}), do: {:ok, nil}
  defp validate_adapter_result({:ok, config}), do: Store.open(config)
  defp validate_adapter_result({:error, _reason} = error), do: error

  defp build_record(agent, instance, opts, ref) do
    partition = Keyword.get(opts, :partition)
    revision = Keyword.get(opts, :revision, 0)
    agent_revision = Keyword.get(opts, :agent_revision, revision)
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
           Record.build_active(
             agent,
             ref,
             revision,
             agent_revision,
             checkpoint,
             Keyword.get(opts, :server_turn)
           ) do
      {:ok, record}
    else
      false -> {:error, {:invalid_checkpoint, :shape}}
      {:error, _reason} = error -> error
    end
  end

  defp delete_current(adapter, adapter_opts, ref, agent_module) do
    case read_for_delete({adapter, adapter_opts}, Record.agent_key(ref)) do
      {:error, :not_found} ->
        with {:ok, tombstone} <- Record.build_tombstone(ref, agent_module, 0, 0),
             {:ok, value} <- Record.encode(tombstone) do
          Store.compare_and_swap(
            {adapter, adapter_opts},
            Record.agent_key(ref),
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
                     Record.build_tombstone(
                       ref,
                       agent_module,
                       Record.revision(current) + 1,
                       Record.agent_revision(current)
                     ),
                   {:ok, value} <- Record.encode(tombstone) do
                Store.compare_and_swap(
                  {adapter, adapter_opts},
                  Record.agent_key(ref),
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
      {:error, %Error.ExecutionError{details: %{code: :persistence_callback_failed} = details} = error} ->
        {:error, %{error | details: Map.put(details, :operation, :delete)}}

      result ->
        result
    end
  end

  @doc false
  @spec portable_term?(term()) :: boolean()
  def portable_term?(term), do: Term.valid?(term)
end
