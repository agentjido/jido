defmodule Jido.AgentServer.RegistrationGuard do
  @moduledoc false
  use GenServer

  @watch_interval 10

  def start_link(opts) do
    instance = Keyword.fetch!(opts, :jido)
    GenServer.start_link(__MODULE__, instance, name: Jido.registration_guard_name(instance))
  end

  def claim(instance, key, pid) when is_atom(instance) and is_pid(pid) do
    GenServer.call(Jido.registration_guard_name(instance), {:claim, key, pid})
  catch
    :exit, _reason -> {:error, :registration_guard_unavailable}
  end

  @impl true
  def init(instance) do
    send(self(), :watch_registry)

    {:ok,
     %{
       registry: Jido.registry_name(instance),
       registry_pid: nil,
       registry_ref: nil,
       claims: %{},
       refs: %{}
     }}
  end

  @impl true
  def handle_call({:claim, key, pid}, _from, state) do
    case Map.get(state.claims, key) do
      {^pid, _ref} ->
        {:reply, :ok, state}

      {owner, _ref} when is_pid(owner) ->
        if Process.alive?(owner) do
          {:reply, {:error, {:already_started, owner}}, state}
        else
          state = drop_claim(state, key)
          {:reply, :ok, add_claim(state, key, pid)}
        end

      nil ->
        {:reply, :ok, add_claim(state, key, pid)}
    end
  end

  @impl true
  def handle_info(:watch_registry, state) do
    case Process.whereis(state.registry) do
      pid when is_pid(pid) and pid != state.registry_pid ->
        ref = Process.monitor(pid)
        state = %{state | registry_pid: pid, registry_ref: ref}
        state = seed_claims(state)

        Enum.each(state.claims, fn {_key, {owner, _ref}} ->
          send(owner, {:jido_registry_restarted, pid})
        end)

        {:noreply, state}

      pid when is_pid(pid) ->
        {:noreply, state}

      nil ->
        Process.send_after(self(), :watch_registry, @watch_interval)
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{registry_ref: ref} = state) do
    Process.send_after(self(), :watch_registry, @watch_interval)
    {:noreply, %{state | registry_pid: nil, registry_ref: nil}}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.fetch(state.refs, ref) do
      {:ok, key} -> {:noreply, drop_claim(state, key)}
      :error -> {:noreply, state}
    end
  end

  defp seed_claims(state) do
    entries =
      Registry.select(state.registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}])

    Enum.reduce(entries, state, fn
      {{:agent, _partitioned_id} = key, pid}, acc when is_pid(pid) ->
        if Map.has_key?(acc.claims, key) or not Process.alive?(pid),
          do: acc,
          else: add_claim(acc, key, pid)

      _entry, acc ->
        acc
    end)
  catch
    :exit, _reason -> state
  end

  defp add_claim(state, key, pid) do
    ref = Process.monitor(pid)
    %{state | claims: Map.put(state.claims, key, {pid, ref}), refs: Map.put(state.refs, ref, key)}
  end

  defp drop_claim(state, key) do
    case Map.pop(state.claims, key) do
      {{_pid, ref}, claims} ->
        Process.demonitor(ref, [:flush])
        %{state | claims: claims, refs: Map.delete(state.refs, ref)}

      {nil, _claims} ->
        state
    end
  end

  def registry_key(id, partition), do: {:agent, Jido.partition_key(id, partition)}
end
