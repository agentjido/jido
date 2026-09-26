defmodule Jido.Persistence.Record do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Agent.Ref
  alias Jido.Error
  alias Jido.PortableTerm

  @format_version 3
  @common_keys [:format, :kind, :namespace, :agent_module, :agent_id, :partition, :revision]
  @active_keys @common_keys ++ [:agent_vsn, :checkpoint]

  def format_version, do: @format_version

  @doc false
  @spec build_active(Agent.t(), Ref.t(), non_neg_integer(), map()) ::
          {:ok, map()} | {:error, term()}
  def build_active(%Agent{} = agent, %Ref{} = ref, revision, checkpoint) do
    record = %{
      format: @format_version,
      kind: :active,
      namespace: ref.namespace,
      agent_module: agent.module,
      agent_vsn: agent.vsn,
      agent_id: agent.id,
      partition: ref.partition,
      revision: revision,
      checkpoint: checkpoint
    }

    with :ok <- validate(record, ref, agent.module),
         do: {:ok, record}
  end

  @doc false
  @spec build_tombstone(Ref.t(), module(), non_neg_integer()) :: {:ok, map()} | {:error, term()}
  def build_tombstone(%Ref{} = ref, agent_module, revision) do
    record = %{
      format: @format_version,
      kind: :tombstone,
      namespace: ref.namespace,
      agent_module: agent_module,
      agent_id: ref.id,
      partition: ref.partition,
      revision: revision
    }

    with :ok <- validate(record, ref, agent_module),
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
  @spec validate(term(), Ref.t(), module()) :: :ok | {:error, term()}
  def validate(record, %Ref{} = ref, agent_module) when is_map(record) do
    with :ok <- validate_format_and_kind(record),
         :ok <- validate_exact_shape(record),
         :ok <- validate_identity(record, ref, agent_module),
         :ok <- validate_revision(record),
         :ok <- validate_kind_fields(record) do
      validate_portable(record)
    end
  end

  def validate(_record, _ref, _agent_module), do: invalid(:shape)

  @doc false
  @spec kind(map()) :: :active | :tombstone | :unknown
  def kind(%{format: @format_version, kind: kind}) when kind in [:active, :tombstone], do: kind
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
  def agent_vsn(record), do: Map.get(record, :agent_vsn)

  def require_active(record) do
    case kind(record) do
      :active -> :ok
      :tombstone -> {:error, :deleted}
      :unknown -> {:error, {:invalid_persistence_record, :kind}}
    end
  end

  def require_active_for_write(record) do
    case kind(record) do
      :active -> :ok
      :tombstone -> {:error, :conflict}
      :unknown -> {:error, {:invalid_persistence_record, :kind}}
    end
  end

  defp validate_format_and_kind(record) do
    case {Map.get(record, :format), Map.get(record, :kind)} do
      {@format_version, kind} when kind in [:active, :tombstone] -> :ok
      {@format_version, _kind} -> invalid(:kind)
      {_format, _kind} -> invalid(:format)
    end
  end

  defp validate_exact_shape(%{kind: :active} = record), do: exact_keys(record, @active_keys)
  defp validate_exact_shape(%{kind: :tombstone} = record), do: exact_keys(record, @common_keys)

  defp exact_keys(record, keys) do
    if map_size(record) == length(keys) and Enum.all?(keys, &Map.has_key?(record, &1)),
      do: :ok,
      else: invalid(:shape)
  end

  defp validate_identity(record, ref, agent_module) do
    cond do
      Map.get(record, :namespace) != ref.namespace -> invalid(:namespace)
      Map.get(record, :agent_module) != agent_module -> invalid(:agent_module)
      Map.get(record, :agent_id) != ref.id -> invalid(:agent_id)
      Map.get(record, :partition) != ref.partition -> invalid(:partition)
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

  defp validate_active(record) do
    with :ok <- validate_checkpoint(record), do: validate_agent_vsn(record)
  end

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
