defmodule Jido.AgentServer.RegistrationGuard do
  @moduledoc false
  use GenServer

  @watch_interval 10

  def start_link(opts) do
    instance = Keyword.fetch!(opts, :jido)
    GenServer.start_link(__MODULE__, instance, name: Jido.registration_guard_name(instance))
  end

  def claim(instance, key, pid, activation) do
    GenServer.call(Jido.registration_guard_name(instance), {:claim, key, pid, activation})
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
  def handle_call({:claim, key, pid, activation}, _from, state) do
    case Map.get(state.claims, key) do
      {^pid, _ref, _activation} ->
        {:reply, :ok, state}

      {owner, ref, previous_activation} ->
        stop_orphan(owner, ref, previous_activation)

        if Process.alive?(owner) do
          {:reply, {:error, {:already_started, owner}}, state}
        else
          state = drop_claim(state, key)
          {:reply, :ok, add_claim(state, key, pid, activation)}
        end

      nil ->
        {:reply, :ok, add_claim(state, key, pid, activation)}
    end
  end

  @impl true
  def handle_info(:watch_registry, state) do
    current = state.registry_pid

    case Process.whereis(state.registry) do
      nil ->
        Process.send_after(self(), :watch_registry, @watch_interval)
        {:noreply, state}

      ^current ->
        {:noreply, state}

      pid ->
        ref = Process.monitor(pid)
        state = %{state | registry_pid: pid, registry_ref: ref}
        {:noreply, seed_claims(state)}
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

  # A killed activation can leave its trapping Server alive during shutdown.
  # Stop that orphan before OTP starts another Server with the same identity.
  defp stop_orphan(owner, ref, activation) when is_pid(activation) do
    if not Process.alive?(activation) do
      Process.exit(owner, :kill)

      receive do
        {:DOWN, ^ref, :process, ^owner, _reason} -> :ok
      after
        1_000 -> :ok
      end
    end
  end

  defp stop_orphan(_owner, _ref, _activation), do: nil

  defp seed_claims(state) do
    entries =
      Registry.select(state.registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}])

    Enum.reduce(entries, state, fn
      {{:agent, _partitioned_id} = key, pid}, acc when is_pid(pid) ->
        if Map.has_key?(acc.claims, key) or not Process.alive?(pid),
          do: acc,
          else: add_claim(acc, key, pid, nil)

      _entry, acc ->
        acc
    end)
  catch
    :exit, _reason -> state
  end

  defp add_claim(state, key, pid, activation) do
    ref = Process.monitor(pid)

    %{
      state
      | claims: Map.put(state.claims, key, {pid, ref, activation}),
        refs: Map.put(state.refs, ref, key)
    }
  end

  defp drop_claim(state, key) do
    {{_pid, ref, _activation}, claims} = Map.pop(state.claims, key)
    %{state | claims: claims, refs: Map.delete(state.refs, ref)}
  end

  def registry_key(id, partition), do: {:agent, Jido.partition_key(id, partition)}
end
