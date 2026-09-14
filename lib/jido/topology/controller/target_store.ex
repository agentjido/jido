defmodule Jido.Topology.Controller.TargetStore do
  @moduledoc false

  alias Jido.Persistence
  alias Jido.PortableTerm
  alias Jido.Topology
  alias Jido.Topology.Instance

  @format 1
  @hive :topology_targets
  @placements :topology_placements
  @key_prefix "jido:topology:v1:"

  def load(jido, %Instance{} = initial) do
    with {:ok, adapter} <- Persistence.resolve_config(:inherit, jido) do
      case adapter do
        nil -> load_local(jido, initial)
        {module, opts} -> load_durable(module, opts, key(jido, initial.id), initial)
      end
    end
  end

  def accept(jido, revision, %Instance{} = target, placements) do
    with {:ok, adapter} <- Persistence.resolve_config(:inherit, jido) do
      case adapter do
        nil ->
          accept_local(jido, revision, target, placements)

        {module, opts} ->
          accept_durable(module, opts, key(jido, target.id), revision, target, placements)
      end
    end
  end

  def forget_local(jido, id) do
    with :ok <- Jido.RuntimeStore.delete(jido, @hive, id),
         do: Jido.RuntimeStore.delete(jido, @placements, id)
  end

  defp load_local(jido, initial) do
    case Jido.RuntimeStore.get(jido, @hive, initial.id) do
      %{instance: target, revision: revision, placements: placements}
      when is_integer(revision) and revision > 0 and is_map(placements) ->
        validate_target(initial, target, revision, placements)

      nil ->
        placements =
          case Jido.RuntimeStore.get(jido, @placements, initial.id) do
            %{definition: definition, placements: saved}
            when definition == initial.definition and is_map(saved) ->
              saved

            _ ->
              %{}
          end

        {:ok, initial, 0, Map.take(placements, Map.keys(initial.plan.agents))}

      _ ->
        {:error, :invalid_topology_target}
    end
  end

  defp accept_local(jido, revision, target, placements) do
    next = revision + 1

    with :ok <-
           Jido.RuntimeStore.put(jido, @hive, target.id, %{
             instance: target,
             revision: next,
             placements: placements
           }),
         :ok <-
           Jido.RuntimeStore.put(jido, @placements, target.id, %{
             definition: target.definition,
             placements: placements
           }) do
      {:ok, next}
    end
  end

  defp load_durable(module, opts, key, initial) do
    case read(module, key, opts) do
      {:ok, :not_found, _condition} -> {:ok, initial, 0, %{}}
      {:ok, bytes, _condition} -> decode(bytes, initial)
      {:error, reason} -> {:error, {:topology_target_restore_failed, reason}}
    end
  end

  defp accept_durable(module, opts, key, revision, target, placements) do
    with :ok <- portable(target, placements),
         {:ok, value, condition} <- read(module, key, opts),
         :ok <- expected_revision(value, target.id, revision),
         next = revision + 1,
         bytes <-
           :erlang.term_to_binary(%{
             format: @format,
             id: target.id,
             revision: next,
             definition: target.definition,
             input: target.input,
             placements: placements
           }),
         :ok <- write(module, key, condition, bytes, opts) do
      {:ok, next}
    end
  end

  defp portable(target, placements) do
    case PortableTerm.validate(
           %{definition: target.definition, input: target.input, placements: placements},
           :topology
         ) do
      :ok -> :ok
      {:error, path} -> {:error, {:nonportable_topology_target, path}}
    end
  end

  defp expected_revision(:not_found, _id, 0), do: :ok
  defp expected_revision(:not_found, _id, _revision), do: {:error, :conflict}

  defp expected_revision(bytes, id, revision) do
    case decode_record(bytes) do
      {:ok, %{id: ^id, revision: ^revision}} -> :ok
      {:ok, _record} -> {:error, :conflict}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode(bytes, initial) do
    with {:ok,
          %{
            id: id,
            revision: revision,
            definition: definition,
            input: input,
            placements: placements
          }} <- decode_record(bytes),
         :ok <- if(id == initial.id, do: :ok, else: {:error, :topology_target_identity_mismatch}),
         {:ok, target} <- Topology.instantiate(definition, id: id, input: input),
         :ok <- portable(target, placements) do
      validate_target(initial, target, revision, placements)
    end
  end

  defp decode_record(bytes) when is_binary(bytes) do
    case :erlang.binary_to_term(bytes, [:safe]) do
      %{
        format: @format,
        id: id,
        revision: revision,
        definition: %Topology{},
        input: input,
        placements: placements
      } = record
      when is_binary(id) and is_integer(revision) and revision > 0 and is_map(input) and
             is_map(placements) ->
        if Map.keys(record) |> Enum.sort() == [
             :definition,
             :format,
             :id,
             :input,
             :placements,
             :revision
           ],
           do: {:ok, record},
           else: {:error, :invalid_topology_target}

      _ ->
        {:error, :invalid_topology_target}
    end
  rescue
    ArgumentError -> {:error, :invalid_topology_target}
  end

  defp validate_target(initial, %Instance{} = target, revision, placements) do
    unchanged? =
      initial.plan.resources == target.plan.resources and
        Enum.all?(initial.plan.agents, fn {key, spec} ->
          Map.get(target.plan.agents, key) == spec
        end)

    if target.id == initial.id and unchanged? do
      {:ok, target, revision, Map.take(placements, Map.keys(target.plan.agents))}
    else
      {:error, :incompatible_topology_target}
    end
  end

  defp validate_target(_initial, _target, _revision, _placements),
    do: {:error, :invalid_topology_target}

  defp read(module, key, opts) do
    case safe_call(fn -> apply(module, :get, [key, opts]) end) do
      {:ok, bytes} when is_binary(bytes) ->
        {:ok, bytes, bytes}

      {:ok, bytes, token} when is_binary(bytes) and is_binary(token) and byte_size(token) > 0 ->
        {:ok, bytes, {:token, token}}

      {:error, :not_found} ->
        {:ok, :not_found, :not_found}

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, :invalid_topology_adapter_result}
    end
  end

  defp write(module, key, condition, bytes, opts) do
    case safe_call(fn -> apply(module, :compare_and_swap, [key, condition, bytes, opts]) end) do
      :ok -> :ok
      {:error, :conflict} = error -> error
      {:error, {:rejected, _}} = error -> error
      {:error, :indeterminate} -> {:error, {:indeterminate, :unknown}}
      {:error, {:indeterminate, _}} = error -> error
      {:error, reason} -> {:error, {:indeterminate, reason}}
      other -> {:error, {:indeterminate, {:invalid_topology_adapter_result, other}}}
    end
  end

  defp safe_call(fun) do
    fun.()
  rescue
    error -> {:error, {:callback_failed, :error, error}}
  catch
    kind, reason -> {:error, {:callback_failed, kind, reason}}
  end

  defp key(jido, id) do
    namespace = Jido.namespace(jido) || Atom.to_string(jido)
    @key_prefix <> Base.url_encode64(:erlang.term_to_binary({namespace, id}), padding: false)
  end
end
