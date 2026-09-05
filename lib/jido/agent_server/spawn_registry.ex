defmodule Jido.AgentServer.SpawnRegistry do
  @moduledoc false
  use GenServer

  alias Jido.RuntimeStore
  @hive :agent_spawn_requests

  def start_link(opts) do
    jido = Keyword.fetch!(opts, :jido)
    GenServer.start_link(__MODULE__, jido, name: name(jido))
  end

  def claim(jido, parent), do: GenServer.call(name(jido), {:claim, parent})
  def started(jido, parent, pid), do: GenServer.call(name(jido), {:started, parent, pid})
  def failed(jido, parent), do: GenServer.call(name(jido), {:failed, parent})
  def retire(jido, pid), do: GenServer.call(name(jido), {:retire, pid})
  def name(jido), do: Module.concat(jido, SpawnRegistry)

  @impl true
  def init(jido) do
    :ok = :net_kernel.monitor_nodes(true)
    requests = Map.new(RuntimeStore.list(jido, @hive))
    owners = requests |> Map.keys() |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    monitors = Map.new(owners, fn owner -> {owner, Process.monitor(owner)} end)
    by_pid = for {key, %{pid: pid}} <- requests, is_pid(pid), into: %{}, do: {pid, key}
    {:ok, %{jido: jido, requests: requests, monitors: monitors, by_pid: by_pid}}
  end

  # Claims execute in the target DynamicSupervisor's serialized start_link
  # callback. Only the newest generation for one parent/tag is retained.
  @impl true
  def handle_call({:claim, parent}, _from, state) do
    key = {parent.pid, parent.tag}
    {generation, _ref} = parent.spawn_ref
    entry = Map.get(state.requests, key)

    cond do
      entry && entry.request_id == parent.spawn_ref && entry.status == :closed ->
        {:reply, :closed, state}

      entry && elem(entry.request_id, 0) > generation ->
        {:reply, :closed, state}

      entry && is_pid(entry.pid) && Process.alive?(entry.pid) ->
        if entry.request_id == parent.spawn_ref,
          do: {:reply, {:existing, entry.pid}, state},
          else: {:reply, {:error, :child_tag_in_use}, state}

      true ->
        entry = %{request_id: parent.spawn_ref, pid: nil, status: :starting}
        {:reply, :ok, put_entry(state, key, entry)}
    end
  end

  def handle_call({:started, parent, pid}, _from, state) do
    key = {parent.pid, parent.tag}

    case Map.get(state.requests, key) do
      %{request_id: request, status: :starting} = entry when request == parent.spawn_ref ->
        {:reply, :ok, put_entry(state, key, %{entry | pid: pid, status: :active})}

      _ ->
        {:reply, {:error, :spawn_request_closed}, state}
    end
  end

  def handle_call({:retire, pid}, _from, state) do
    case Map.get(state.by_pid, pid) do
      nil -> {:reply, :ok, state}
      key -> {:reply, :ok, put_entry(state, key, %{state.requests[key] | status: :closed})}
    end
  end

  def handle_call({:failed, parent}, _from, state) do
    key = {parent.pid, parent.tag}

    case Map.get(state.requests, key) do
      %{request_id: request} = entry when request == parent.spawn_ref ->
        {:reply, :ok, put_entry(state, key, %{entry | status: :closed})}

      _ ->
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, owner, :noconnection}, state) do
    if Map.get(state.monitors, owner) == ref do
      # Connection loss is not proof of parent death. Preserve the latest
      # generation so a late request cannot recreate a child after reconnect.
      next =
        Enum.reduce(state.requests, state, fn
          {{^owner, _} = key, entry}, acc -> put_entry(acc, key, %{entry | status: :closed})
          _, acc -> acc
        end)

      {:noreply, %{next | monitors: Map.delete(next.monitors, owner)}}
    else
      {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, owner, _reason}, state) do
    if Map.get(state.monitors, owner) == ref do
      {removed, kept} = Enum.split_with(state.requests, fn {{pid, _tag}, _} -> pid == owner end)
      Enum.each(removed, fn {key, _} -> RuntimeStore.delete(state.jido, @hive, key) end)
      by_pid = Map.reject(state.by_pid, fn {_pid, {parent, _}} -> parent == owner end)

      {:noreply,
       %{
         state
         | requests: Map.new(kept),
           monitors: Map.delete(state.monitors, owner),
           by_pid: by_pid
       }}
    else
      {:noreply, state}
    end
  end

  def handle_info({:nodeup, target}, state) do
    monitors =
      Enum.reduce(state.requests, state.monitors, fn {{owner, _}, _}, acc ->
        if node(owner) == target,
          do: Map.put_new_lazy(acc, owner, fn -> Process.monitor(owner) end),
          else: acc
      end)

    {:noreply, %{state | monitors: monitors}}
  end

  def handle_info({:nodedown, _target}, state), do: {:noreply, state}

  defp put_entry(state, {owner, _tag} = key, entry) do
    :ok = RuntimeStore.put(state.jido, @hive, key, entry)
    monitors = Map.put_new_lazy(state.monitors, owner, fn -> Process.monitor(owner) end)
    previous = Map.get(state.requests, key, %{})[:pid]
    by_pid = Map.delete(state.by_pid, previous)
    by_pid = if is_pid(entry.pid), do: Map.put(by_pid, entry.pid, key), else: by_pid
    %{state | requests: Map.put(state.requests, key, entry), monitors: monitors, by_pid: by_pid}
  end
end
