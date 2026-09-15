defmodule Jido.Persistence.Record do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Error
  alias Jido.PortableTerm

  @legacy_format_version 1
  @format_version 2
  @ref_format_version 3

  @common_keys [:format, :kind, :agent_module, :agent_id, :partition, :revision]
  @active_keys @common_keys ++ [:instance, :agent_vsn, :checkpoint]
  @tombstone_keys @common_keys ++ [:instance]
  @ref_active_keys @common_keys ++ [:namespace, :agent_vsn, :checkpoint]
  @ref_tombstone_keys @common_keys ++ [:namespace]

  @doc false
  @spec format_version() :: pos_integer()
  def format_version, do: @format_version

  @doc false
  @spec ref_format_version() :: pos_integer()
  def ref_format_version, do: @ref_format_version

  @doc false
  @spec build_active(Agent.t(), atom() | nil, term(), non_neg_integer(), map()) ::
          {:ok, map()} | {:error, term()}
  def build_active(%Agent{} = agent, instance, partition, revision, checkpoint) do
    record = %{
      format: @format_version,
      kind: :active,
      instance: instance,
      agent_module: agent.module,
      agent_vsn: agent.vsn,
      agent_id: agent.id,
      partition: partition,
      revision: revision,
      checkpoint: checkpoint
    }

    with :ok <- validate(record, instance, agent.module, agent.id, partition), do: {:ok, record}
  end

  @doc false
  @spec build_tombstone(atom() | nil, module(), String.t(), term(), non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  def build_tombstone(instance, agent_module, agent_id, partition, revision) do
    record = %{
      format: @format_version,
      kind: :tombstone,
      instance: instance,
      agent_module: agent_module,
      agent_id: agent_id,
      partition: partition,
      revision: revision
    }

    with :ok <- validate(record, instance, agent_module, agent_id, partition), do: {:ok, record}
  end

  @doc false
  @spec build_ref_active(Agent.t(), String.t(), String.t() | nil, non_neg_integer(), map()) ::
          {:ok, map()} | {:error, term()}
  def build_ref_active(%Agent{} = agent, namespace, partition, revision, checkpoint) do
    record = %{
      format: @ref_format_version,
      kind: :active,
      namespace: namespace,
      agent_module: agent.module,
      agent_vsn: agent.vsn,
      agent_id: agent.id,
      partition: partition,
      revision: revision,
      checkpoint: checkpoint
    }

    with :ok <- validate_ref(record, namespace, agent.module, agent.id, partition),
         do: {:ok, record}
  end

  @doc false
  @spec build_ref_tombstone(
          String.t(),
          module(),
          String.t(),
          String.t() | nil,
          non_neg_integer()
        ) :: {:ok, map()} | {:error, term()}
  def build_ref_tombstone(namespace, agent_module, agent_id, partition, revision) do
    record = %{
      format: @ref_format_version,
      kind: :tombstone,
      namespace: namespace,
      agent_module: agent_module,
      agent_id: agent_id,
      partition: partition,
      revision: revision
    }

    with :ok <- validate_ref(record, namespace, agent_module, agent_id, partition),
         do: {:ok, record}
  end

  @doc false
  @spec encode(map()) :: {:ok, binary()} | {:error, term()}
  def encode(record) do
    {:ok, :erlang.term_to_binary(record)}
  rescue
    error -> {:error, {:checkpoint_encode_failed, error}}
  end

  @doc false
  @spec decode(term()) :: {:ok, term()} | {:error, :invalid_persistence_record}
  def decode(value) when is_binary(value) do
    {:ok, :erlang.binary_to_term(value, [:safe])}
  rescue
    ArgumentError -> {:error, :invalid_persistence_record}
  end

  def decode(_value), do: {:error, :invalid_persistence_record}

  @doc false
  @spec validate(term(), atom() | nil, module(), String.t(), term()) :: :ok | {:error, term()}
  def validate(record, instance, agent_module, agent_id, partition) when is_map(record) do
    with :ok <- validate_format_and_kind(record),
         :ok <- validate_exact_shape(record),
         :ok <- validate_identity(record, :instance, instance, agent_module, agent_id, partition),
         :ok <- validate_revision(record),
         :ok <- validate_kind_fields(record),
         :ok <- validate_portable(record) do
      :ok
    end
  end

  def validate(_record, _instance, _agent_module, _agent_id, _partition),
    do: invalid(:shape)

  @doc false
  @spec validate_ref(term(), String.t(), module(), String.t(), String.t() | nil) ::
          :ok | {:error, term()}
  def validate_ref(record, namespace, agent_module, agent_id, partition)
      when is_map(record) do
    with :ok <- validate_format_and_kind(record),
         true <- Map.get(record, :format) == @ref_format_version,
         :ok <- validate_exact_shape(record),
         :ok <-
           validate_identity(record, :namespace, namespace, agent_module, agent_id, partition),
         :ok <- validate_revision(record),
         :ok <- validate_kind_fields(record),
         :ok <- validate_portable(record) do
      :ok
    else
      false -> invalid(:format)
      {:error, _reason} = error -> error
    end
  end

  def validate_ref(_record, _namespace, _agent_module, _agent_id, _partition),
    do: invalid(:shape)

  @doc false
  @spec kind(map()) :: :active | :tombstone | :unknown
  def kind(%{format: @legacy_format_version, kind: :agent}), do: :active
  def kind(%{format: @format_version, kind: :active}), do: :active
  def kind(%{format: @format_version, kind: :tombstone}), do: :tombstone
  def kind(%{format: @ref_format_version, kind: :active}), do: :active
  def kind(%{format: @ref_format_version, kind: :tombstone}), do: :tombstone
  def kind(_record), do: :unknown

  @doc false
  @spec format(map()) :: term()
  def format(record), do: Map.get(record, :format)

  @doc false
  @spec revision(map()) :: term()
  def revision(record), do: Map.get(record, :revision)

  @doc false
  @spec checkpoint(map()) :: term()
  def checkpoint(record), do: Map.get(record, :checkpoint)

  @doc false
  @spec agent_vsn(map()) :: term()
  def agent_vsn(%{format: format, kind: :active} = record)
      when format in [@format_version, @ref_format_version],
      do: Map.get(record, :agent_vsn)

  def agent_vsn(_record), do: nil

  defp validate_format_and_kind(record) do
    case {Map.get(record, :format), Map.get(record, :kind)} do
      {@legacy_format_version, :agent} -> :ok
      {@format_version, :active} -> :ok
      {@format_version, :tombstone} -> :ok
      {@ref_format_version, :active} -> :ok
      {@ref_format_version, :tombstone} -> :ok
      {@legacy_format_version, _kind} -> invalid(:kind)
      {@format_version, _kind} -> invalid(:kind)
      {@ref_format_version, _kind} -> invalid(:kind)
      {_format, _kind} -> invalid(:format)
    end
  end

  defp validate_exact_shape(%{format: @legacy_format_version}), do: :ok

  defp validate_exact_shape(%{format: @ref_format_version, kind: :active} = record),
    do: exact_keys(record, @ref_active_keys)

  defp validate_exact_shape(%{format: @ref_format_version, kind: :tombstone} = record),
    do: exact_keys(record, @ref_tombstone_keys)

  defp validate_exact_shape(%{format: @format_version, kind: :active} = record),
    do: exact_keys(record, @active_keys)

  defp validate_exact_shape(%{format: @format_version, kind: :tombstone} = record),
    do: exact_keys(record, @tombstone_keys)

  defp exact_keys(record, keys) do
    if Enum.sort(Map.keys(record)) == Enum.sort(keys), do: :ok, else: invalid(:shape)
  end

  defp validate_identity(record, scope_field, scope, agent_module, agent_id, partition) do
    cond do
      Map.get(record, scope_field) != scope -> invalid(scope_field)
      Map.get(record, :agent_module) != agent_module -> invalid(:agent_module)
      Map.get(record, :agent_id) != agent_id -> invalid(:agent_id)
      Map.get(record, :partition) != partition -> invalid(:partition)
      true -> :ok
    end
  end

  defp validate_revision(record) do
    revision = Map.get(record, :revision)
    if is_integer(revision) and revision >= 0, do: :ok, else: invalid(:revision)
  end

  defp validate_kind_fields(record) do
    case kind(record) do
      :active -> validate_active(record)
      :tombstone -> :ok
      :unknown -> invalid(:kind)
    end
  end

  defp validate_active(%{format: format} = record)
       when format in [@format_version, @ref_format_version] do
    with :ok <- validate_checkpoint(record), do: validate_agent_vsn(record)
  end

  defp validate_active(record), do: validate_checkpoint(record)

  defp validate_checkpoint(record) do
    checkpoint = Map.get(record, :checkpoint)

    if is_map(checkpoint) and not is_struct(checkpoint),
      do: :ok,
      else: invalid(:checkpoint)
  end

  defp validate_agent_vsn(%{agent_vsn: nil}), do: :ok
  defp validate_agent_vsn(%{agent_vsn: vsn}) when is_integer(vsn) and vsn > 0, do: :ok
  defp validate_agent_vsn(_record), do: invalid(:agent_vsn)

  defp validate_portable(record) do
    case PortableTerm.validate(record, :record) do
      :ok ->
        :ok

      {:error, path} ->
        {:error,
         Error.validation_error("Persistence record contains a non-portable term",
           kind: :config,
           details: %{code: :non_portable_term, path: path}
         )}
    end
  end

  defp invalid(field), do: {:error, {:invalid_persistence_record, field}}
end
