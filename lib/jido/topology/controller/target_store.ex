defmodule Jido.Topology.Controller.TargetStore do
  @moduledoc false

  alias Jido.Persistence
  alias Jido.Persistence.Store
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
    write_target(jido, revision, target, placements, nil)
  end

  def accept_placement(jido, revision, %Instance{} = target, placements, move) do
    write_target(jido, revision, target, placements, move)
  end

  def complete_placement(jido, revision, %Instance{} = target, placements) do
    write_target(jido, revision, target, placements, nil)
  end

  defp write_target(jido, revision, target, placements, pending_move) do
    with {:ok, adapter} <- Persistence.resolve_config(:inherit, jido) do
      case adapter do
        nil ->
          accept_local(jido, revision, target, placements, pending_move)

        {module, opts} ->
          accept_durable(
            module,
            opts,
            key(jido, target.id),
            revision,
            target,
            placements,
            pending_move
          )
      end
    end
  end

  def forget_local(jido, id) do
    with :ok <- Jido.RuntimeStore.delete(jido, @hive, id),
         do: Jido.RuntimeStore.delete(jido, @placements, id)
  end

  defp load_local(jido, initial) do
    case Jido.RuntimeStore.get(jido, @hive, initial.id) do
      %{instance: target, revision: revision, placements: placements} = record
      when is_integer(revision) and revision > 0 and is_map(placements) ->
        validate_target(initial, target, revision, placements, Map.get(record, :pending_move))

      nil ->
        placements =
          case Jido.RuntimeStore.get(jido, @placements, initial.id) do
            %{definition: definition, placements: saved}
            when definition == initial.definition and is_map(saved) ->
              saved

            _ ->
              %{}
          end

        {:ok, initial, 0, Map.take(placements, Map.keys(initial.plan.agents)), nil}

      _ ->
        {:error, :invalid_topology_target}
    end
  end

  defp accept_local(jido, revision, target, placements, pending_move) do
    next = revision + 1

    with :ok <-
           Jido.RuntimeStore.put(jido, @hive, target.id, %{
             instance: target,
             revision: next,
             placements: placements,
             pending_move: pending_move
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
      {:ok, :not_found, _condition} -> {:ok, initial, 0, %{}, nil}
      {:ok, bytes, _condition} -> decode(bytes, initial)
      {:error, reason} -> {:error, {:topology_target_restore_failed, reason}}
    end
  end

  defp accept_durable(module, opts, key, revision, target, placements, pending_move) do
    with :ok <- portable(target, placements, pending_move),
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
             placements: placements,
             pending_move: pending_move
           }),
         :ok <- write(module, key, condition, bytes, opts) do
      {:ok, next}
    end
  end

  defp portable(target, placements, pending_move) do
    case PortableTerm.validate(
           %{
             definition: target.definition,
             input: target.input,
             placements: placements,
             pending_move: pending_move
           },
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
          } = record} <- decode_record(bytes),
         :ok <- if(id == initial.id, do: :ok, else: {:error, :topology_target_identity_mismatch}),
         {:ok, target} <- Topology.instantiate(definition, id: id, input: input),
         pending_move = Map.get(record, :pending_move),
         :ok <- portable(target, placements, pending_move) do
      validate_target(initial, target, revision, placements, pending_move)
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
        if Enum.sort(Map.keys(record)) in [
             [:definition, :format, :id, :input, :placements, :revision],
             [:definition, :format, :id, :input, :pending_move, :placements, :revision]
           ],
           do: {:ok, record},
           else: {:error, :invalid_topology_target}

      _ ->
        {:error, :invalid_topology_target}
    end
  rescue
    ArgumentError -> {:error, :invalid_topology_target}
  end

  defp validate_target(initial, %Instance{} = target, revision, placements, pending_move) do
    unchanged? =
      initial.plan.resources == target.plan.resources and
        Enum.all?(initial.plan.agents, fn {key, spec} ->
          Map.get(target.plan.agents, key) == spec
        end)

    if target.id == initial.id and unchanged? and valid_move?(target, placements, pending_move) do
      {:ok, target, revision, Map.take(placements, Map.keys(target.plan.agents)), pending_move}
    else
      {:error, :incompatible_topology_target}
    end
  end

  defp validate_target(_initial, _target, _revision, _placements, _pending_move),
    do: {:error, :invalid_topology_target}

  defp valid_move?(_target, _placements, nil), do: true

  defp valid_move?(target, placements, %{key: key, from: from, to: to} = move) do
    move == %{key: key, from: from, to: to} and is_binary(key) and
      is_atom(from) and is_atom(to) and Map.has_key?(target.plan.agents, key) and
      Map.get(placements, key) == to
  end

  defp valid_move?(_target, _placements, _move), do: false

  defp read(module, key, opts) do
    case Store.read({module, opts}, key) do
      {:ok, bytes, condition} ->
        {:ok, bytes, condition}

      {:error, :not_found} ->
        {:ok, :not_found, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp write(module, key, condition, bytes, opts) do
    case Store.compare_and_swap({module, opts}, key, condition, bytes) do
      {:error, :indeterminate} -> {:error, {:indeterminate, :unknown}}
      result -> result
    end
  end

  defp key(jido, id) do
    namespace = Jido.namespace(jido) || Atom.to_string(jido)
    @key_prefix <> Base.url_encode64(:erlang.term_to_binary({namespace, id}), padding: false)
  end
end
