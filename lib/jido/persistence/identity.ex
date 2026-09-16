defmodule Jido.Persistence.Identity do
  @moduledoc false

  alias Jido.Agent.Ref
  alias Jido.Persistence.{AdapterOps, Source, WriteAuthority}

  @key_prefix "jido:agent:v1:"

  def establish_write_authority(source, agent_module, agent_id, opts)
      when is_atom(agent_module) and is_binary(agent_id) do
    AdapterOps.protect(:get, fn ->
      with :ok <- Source.validate_operation_options(opts),
           namespace when is_binary(namespace) <- Keyword.get(opts, :namespace),
           {:ok, {adapter, adapter_opts}, instance} <- Source.resolve(source, opts),
           partition = Keyword.get(opts, :partition),
           {:ok, ref} <- Ref.new(namespace: namespace, partition: partition, id: agent_id),
           ref_identity = %{mode: :ref, key: agent_key(ref), namespace: namespace},
           legacy_identity = %{
             mode: :legacy,
             key: agent_key(instance, agent_module, agent_id, partition)
           },
           {:ok, selected} <-
             select_storage_identity(adapter, adapter_opts, ref_identity, legacy_identity) do
        other_key =
          if selected.mode == :ref, do: legacy_identity.key, else: ref_identity.key

        {:ok,
         %WriteAuthority{
           instance: instance,
           agent_module: agent_module,
           agent_id: agent_id,
           partition: partition,
           namespace: namespace,
           mode: selected.mode,
           key: selected.key,
           other_key: other_key
         }}
      else
        nil -> {:error, :stable_namespace_required}
        {:error, _reason} = error -> error
        _other -> {:error, :stable_namespace_required}
      end
    end)
  end

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
    @key_prefix <> Base.url_encode64(identity, padding: false)
  end

  def resolve({adapter, adapter_opts}, instance, agent_module, agent_id, opts) do
    case Keyword.get(opts, :write_authority) do
      nil ->
        discover_storage_identity(adapter, adapter_opts, instance, agent_module, agent_id, opts)

      %WriteAuthority{} = authority ->
        authority_storage_identity(
          adapter,
          adapter_opts,
          authority,
          instance,
          agent_module,
          agent_id,
          opts
        )

      _invalid ->
        {:error, :invalid_persistence_write_authority}
    end
  end

  defp discover_storage_identity(adapter, adapter_opts, instance, agent_module, agent_id, opts) do
    partition = Keyword.get(opts, :partition)

    case Keyword.get(opts, :namespace) do
      nil ->
        {:ok, %{mode: :legacy, key: agent_key(instance, agent_module, agent_id, partition)}}

      namespace ->
        with {:ok, ref} <- Ref.new(namespace: namespace, partition: partition, id: agent_id) do
          ref_identity = %{mode: :ref, key: agent_key(ref), namespace: namespace}

          legacy_identity = %{
            mode: :legacy,
            key: agent_key(instance, agent_module, agent_id, partition)
          }

          select_storage_identity(adapter, adapter_opts, ref_identity, legacy_identity)
        end
    end
  end

  defp authority_storage_identity(
         adapter,
         adapter_opts,
         authority,
         instance,
         agent_module,
         agent_id,
         opts
       ) do
    partition = Keyword.get(opts, :partition)
    namespace = Keyword.get(opts, :namespace)

    with :ok <- authority_identity_match(authority, instance, agent_module, agent_id, partition),
         :ok <- authority_namespace_match(authority, namespace),
         :ok <- authority_key_match(authority),
         :missing <- stored_key_state(adapter, authority.other_key, adapter_opts) do
      case authority.mode do
        :legacy -> {:ok, %{mode: :legacy, key: authority.key}}
        :ref -> {:ok, %{mode: :ref, key: authority.key, namespace: authority.namespace}}
      end
    else
      :present ->
        {:error, {:persistence_identity_collision, authority_collision_keys(authority)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp authority_identity_match(authority, instance, agent_module, agent_id, partition) do
    if authority.instance == instance and authority.agent_module == agent_module and
         authority.agent_id == agent_id and authority.partition == partition,
       do: :ok,
       else: {:error, :persistence_write_authority_mismatch}
  end

  defp authority_namespace_match(_authority, nil), do: :ok

  defp authority_namespace_match(%WriteAuthority{namespace: namespace}, namespace), do: :ok

  defp authority_namespace_match(_authority, _namespace),
    do: {:error, :persistence_write_authority_mismatch}

  defp authority_key_match(%WriteAuthority{} = authority) do
    legacy_key =
      agent_key(
        authority.instance,
        authority.agent_module,
        authority.agent_id,
        authority.partition
      )

    with {:ok, ref} <-
           Ref.new(
             namespace: authority.namespace,
             partition: authority.partition,
             id: authority.agent_id
           ) do
      ref_key = agent_key(ref)

      valid? =
        case authority.mode do
          :legacy -> authority.key == legacy_key and authority.other_key == ref_key
          :ref -> authority.key == ref_key and authority.other_key == legacy_key
          _invalid -> false
        end

      if valid?, do: :ok, else: {:error, :invalid_persistence_write_authority}
    end
  end

  defp authority_collision_keys(%WriteAuthority{mode: :ref} = authority),
    do: %{ref_key: authority.key, legacy_key: authority.other_key}

  defp authority_collision_keys(%WriteAuthority{} = authority),
    do: %{ref_key: authority.other_key, legacy_key: authority.key}

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
    case AdapterOps.get(adapter, key, opts) do
      {:ok, _value, _condition} -> :present
      {:error, :not_found} -> :missing
      {:error, reason} -> {:error, reason}
    end
  end
end
