defmodule Jido.Persistence.Record do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Agent.Ref
  alias Jido.Error
  alias Jido.Codec.Term
  alias Jido.Persistence.Config

  @format_version 3
  @key_prefix "jido:agent:v3:"
  @common_keys [:fmt, :kind, :namespace, :agent_module, :agent_id, :partition, :rev, :agent_rev]
  @active_keys @common_keys ++ [:vsn, :checkpoint]

  def format_version, do: @format_version

  @doc false
  @spec agent_key(Ref.t()) :: binary()
  def agent_key(%Ref{} = ref) do
    ref = Ref.new!(ref)

    encoded =
      {ref.namespace, ref.partition, ref.id}
      |> :erlang.term_to_binary()
      |> Base.url_encode64(padding: false)

    @key_prefix <> encoded
  end

  @doc false
  @spec build_active(Agent.t(), Ref.t(), non_neg_integer(), non_neg_integer(), map()) ::
          {:ok, map()} | {:error, term()}
  @spec build_active(Agent.t(), Ref.t(), non_neg_integer(), non_neg_integer(), map(), map() | nil) ::
          {:ok, map()} | {:error, term()}
  def build_active(
        %Agent{} = agent,
        %Ref{} = ref,
        revision,
        agent_revision,
        checkpoint,
        server_turn \\ nil
      ) do
    record = %{
      fmt: @format_version,
      kind: :active,
      namespace: ref.namespace,
      agent_module: agent.module,
      vsn: agent.vsn,
      agent_id: agent.id,
      partition: ref.partition,
      rev: revision,
      agent_rev: agent_revision,
      checkpoint: checkpoint
    }

    record = if is_nil(server_turn), do: record, else: Map.put(record, :server_turn, server_turn)

    with :ok <- validate(record, ref, agent.module),
         do: {:ok, record}
  end

  @doc false
  @spec build_tombstone(Ref.t(), module(), non_neg_integer(), non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  def build_tombstone(%Ref{} = ref, agent_module, revision, agent_revision) do
    record = %{
      fmt: @format_version,
      kind: :tombstone,
      namespace: ref.namespace,
      agent_module: agent_module,
      agent_id: ref.id,
      partition: ref.partition,
      rev: revision,
      agent_rev: agent_revision
    }

    with :ok <- validate(record, ref, agent_module),
         do: {:ok, record}
  end

  @doc false
  @spec encode(map()) :: {:ok, binary()} | {:error, term()}
  def encode(record), do: Jido.Persistence.Codec.Term.encode(record)

  @doc false
  @spec encode(map(), Config.t()) :: {:ok, binary()} | {:error, term()}
  def encode(record, %Config{} = config), do: Config.encode(config, record)

  @doc false
  @spec decode(term()) :: {:ok, term()} | {:error, :invalid_persistence_record}
  def decode(value) do
    # Load the trusted envelope fields before safe decoding on a cold node.
    _ = Code.ensure_loaded?(Jido.Persistence.Snapshot)
    _ = Code.ensure_loaded?(Jido.Signal)

    case Jido.Persistence.Codec.Term.decode(value, []) do
      {:ok, record} -> {:ok, record}
      {:error, _reason} -> {:error, :invalid_persistence_record}
    end
  end

  @doc false
  @spec decode(term(), Config.t()) :: {:ok, term()} | {:error, :invalid_persistence_record}
  def decode(value, %Config{} = config) do
    _ = Code.ensure_loaded?(Jido.Persistence.Snapshot)
    _ = Code.ensure_loaded?(Jido.Signal)

    case Config.decode(config, value) do
      {:ok, record} -> {:ok, record}
      {:error, _reason} -> {:error, :invalid_persistence_record}
    end
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
  def kind(_record), do: :unknown

  @doc false
  @spec format(map()) :: term()
  def format(record), do: Map.get(record, :fmt)

  @doc false
  @spec revision(map()) :: term()
  def revision(record), do: Map.get(record, :rev)

  @doc false
  @spec agent_revision(map()) :: term()
  def agent_revision(record), do: Map.get(record, :agent_rev)

  @doc false
  @spec checkpoint(map()) :: term()
  def checkpoint(record), do: Map.get(record, :checkpoint)

  @doc false
  @spec agent_vsn(map()) :: term()
  def agent_vsn(record), do: Map.get(record, :vsn)

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
    cond do
      Map.get(record, :fmt) != @format_version -> invalid(:fmt)
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

  defp validate_exact_shape(record), do: exact_keys(record, @common_keys)

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
    agent_revision = agent_revision(record)

    if is_integer(revision) and revision >= 0 and is_integer(agent_revision) and
         agent_revision >= 0 and agent_revision <= revision,
       do: :ok,
       else: invalid(:rev)
  end

  defp validate_kind_fields(%{kind: :active} = record), do: validate_active(record)
  defp validate_kind_fields(_record), do: :ok

  defp validate_active(record) do
    with :ok <- validate_checkpoint(record),
         :ok <- validate_agent_vsn(record),
         do: validate_server_turn(Map.get(record, :server_turn))
  end

  defp validate_server_turn(nil), do: :ok

  defp validate_server_turn(turn) do
    case Jido.Durable.Continuation.validate(turn) do
      :ok -> :ok
      {:error, _reason} -> invalid(:server_turn)
    end
  end

  defp validate_checkpoint(record) do
    checkpoint = Map.get(record, :checkpoint)

    if is_map(checkpoint) and not is_struct(checkpoint),
      do: :ok,
      else: invalid(:checkpoint)
  end

  defp validate_agent_vsn(record) do
    case agent_vsn(record) do
      vsn when is_integer(vsn) and vsn > 0 -> :ok
      _ -> invalid(:vsn)
    end
  end

  defp validate_portable(record) do
    case Term.validate(record, :record) do
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
