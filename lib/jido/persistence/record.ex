defmodule Jido.Persistence.Record do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Agent.Ref
  alias Jido.Error
  alias Jido.PortableTerm

  @format_version 4
  @common_keys [:fmt, :kind, :namespace, :agent_module, :agent_id, :partition, :rev]
  @active_keys @common_keys ++ [:vsn, :checkpoint]
  @legacy_keys [:format, :kind, :namespace, :agent_module, :agent_id, :partition, :revision]

  def format_version, do: @format_version

  @doc false
  @spec build_active(Agent.t(), Ref.t(), non_neg_integer(), map()) ::
          {:ok, map()} | {:error, term()}
  @spec build_active(Agent.t(), Ref.t(), non_neg_integer(), map(), map() | nil) ::
          {:ok, map()} | {:error, term()}
  def build_active(%Agent{} = agent, %Ref{} = ref, revision, checkpoint, server_turn \\ nil) do
    record = %{
      fmt: @format_version,
      kind: :active,
      namespace: ref.namespace,
      agent_module: agent.module,
      vsn: agent.vsn,
      agent_id: agent.id,
      partition: ref.partition,
      rev: revision,
      checkpoint: checkpoint
    }

    record = if is_nil(server_turn), do: record, else: Map.put(record, :server_turn, server_turn)

    with :ok <- validate(record, ref, agent.module),
         do: {:ok, record}
  end

  @doc false
  @spec build_tombstone(Ref.t(), module(), non_neg_integer()) :: {:ok, map()} | {:error, term()}
  def build_tombstone(%Ref{} = ref, agent_module, revision) do
    record = %{
      fmt: @format_version,
      kind: :tombstone,
      namespace: ref.namespace,
      agent_module: agent_module,
      agent_id: ref.id,
      partition: ref.partition,
      rev: revision
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
  def decode(value) do
    # Load the trusted envelope fields before safe decoding on a cold node.
    _ = Code.ensure_loaded?(Jido.Persistence.Snapshot)
    _ = Code.ensure_loaded?(Jido.Signal)
    {:ok, :erlang.binary_to_term(value, [:safe])}
  rescue
    ArgumentError -> {:error, :invalid_persistence_record}
  end

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
  def kind(%{fmt: @format_version, kind: kind}) when kind in [:active, :tombstone], do: kind
  def kind(%{format: 3, kind: kind}) when kind in [:active, :tombstone], do: kind
  def kind(_record), do: :unknown

  @doc false
  @spec format(map()) :: term()
  def format(record), do: Map.get(record, :fmt, Map.get(record, :format))

  @doc false
  @spec revision(map()) :: term()
  def revision(record), do: Map.get(record, :rev, Map.get(record, :revision))

  @doc false
  @spec checkpoint(map()) :: term()
  def checkpoint(record), do: Map.get(record, :checkpoint)

  @doc false
  @spec agent_vsn(map()) :: term()
  def agent_vsn(record), do: Map.get(record, :vsn, Map.get(record, :agent_vsn))

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
    valid_format? =
      if Map.has_key?(record, :fmt),
        do: record.fmt == @format_version,
        else: Map.get(record, :format) == 3

    cond do
      not valid_format? -> invalid(if(Map.has_key?(record, :fmt), do: :fmt, else: :format))
      Map.get(record, :kind) not in [:active, :tombstone] -> invalid(:kind)
      true -> :ok
    end
  end

  defp validate_exact_shape(%{fmt: _, kind: :active} = record),
    do:
      exact_keys(
        record,
        if(Map.has_key?(record, :server_turn),
          do: @active_keys ++ [:server_turn],
          else: @active_keys
        )
      )

  defp validate_exact_shape(%{fmt: _} = record), do: exact_keys(record, @common_keys)

  defp validate_exact_shape(%{kind: :active} = record),
    do: exact_keys(record, @legacy_keys ++ [:agent_vsn, :checkpoint])

  defp validate_exact_shape(record), do: exact_keys(record, @legacy_keys)

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
    revision = revision(record)

    if is_integer(revision) and revision >= 0,
      do: :ok,
      else: invalid(if(Map.has_key?(record, :fmt), do: :rev, else: :revision))
  end

  defp validate_kind_fields(%{kind: :active} = record), do: validate_active(record)
  defp validate_kind_fields(_record), do: :ok

  defp validate_active(record) do
    with :ok <- validate_checkpoint(record),
         :ok <- validate_agent_vsn(record),
         do: validate_server_turn(Map.get(record, :server_turn))
  end

  defp validate_server_turn(nil), do: :ok

  defp validate_server_turn(
         %{
           id: id,
           status: status,
           signal: %Jido.Signal{},
           context: context,
           fingerprint: fingerprint,
           instruction: %Jido.Instruction{},
           chain_id: chain_id,
           chain_order: chain_order,
           predecessor_id: predecessor_id
         } = turn
       )
       when is_binary(id) and byte_size(id) > 0 and
              status in [:accepted, :failed, :cancelled] and is_map(context) and
              is_binary(fingerprint) and is_binary(chain_id) and byte_size(chain_id) > 0 and
              is_integer(chain_order) and chain_order > 0 and is_binary(predecessor_id) and
              byte_size(predecessor_id) > 0 and map_size(turn) == 9,
       do: :ok

  defp validate_server_turn(
         %{
           id: id,
           status: status,
           signal: %Jido.Signal{},
           admitted_signal: %Jido.Signal{},
           context: context,
           plugin_inputs: inputs,
           fingerprint: fingerprint,
           expires_at: expires_at
         } = turn
       )
       when is_binary(id) and byte_size(id) > 0 and
              status in [:running, :completed, :failed, :cancelled] and
              is_map(context) and is_map(inputs) and is_binary(fingerprint) and
              (expires_at == :infinity or is_integer(expires_at)) and map_size(turn) == 8,
       do: :ok

  defp validate_server_turn(
         %{
           id: id,
           status: status,
           signal: %Jido.Signal{},
           admitted_signal: %Jido.Signal{},
           context: context,
           plugin_inputs: inputs,
           fingerprint: fingerprint,
           expires_at: expires_at,
           instruction: %Jido.Instruction{},
           chain_id: chain_id,
           chain_order: chain_order,
           predecessor_id: predecessor_id
         } = turn
       )
       when is_binary(id) and byte_size(id) > 0 and
              status in [:released, :completed, :failed, :cancelled] and
              is_map(context) and
              is_map(inputs) and
              is_binary(fingerprint) and (expires_at == :infinity or is_integer(expires_at)) and
              is_binary(chain_id) and byte_size(chain_id) > 0 and is_integer(chain_order) and
              chain_order > 0 and is_binary(predecessor_id) and byte_size(predecessor_id) > 0 and
              map_size(turn) == 12,
       do: :ok

  defp validate_server_turn(_), do: invalid(:server_turn)

  defp validate_checkpoint(record) do
    checkpoint = Map.get(record, :checkpoint)

    if is_map(checkpoint) and not is_struct(checkpoint),
      do: :ok,
      else: invalid(:checkpoint)
  end

  defp validate_agent_vsn(record) do
    case agent_vsn(record) do
      vsn when is_integer(vsn) and vsn > 0 -> :ok
      _ -> invalid(if(Map.has_key?(record, :fmt), do: :vsn, else: :agent_vsn))
    end
  end

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
