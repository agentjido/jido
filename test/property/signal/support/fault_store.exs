Code.require_file("model.exs", __DIR__)

defmodule JidoTest.Property.Signal.FaultStore do
  @moduledoc false
  @behaviour Jido.Signal.Bus.Store
  alias Jido.Signal.Bus.Store.Memory
  alias JidoTest.Property.Signal.Model

  def fail(agent, callback, kind), do: Agent.update(agent, &put_in(&1.faults[callback], kind))
  def snapshot(agent), do: Agent.get(agent, & &1.memory)
  def gate_append(agent), do: Agent.update(agent, &%{&1 | gate: true})

  @impl true
  def init(opts),
    do:
      operation(Keyword.fetch!(opts, :agent), :init, fn _ ->
        {:ok, Keyword.fetch!(opts, :agent)}
      end)

  @impl true
  def append(records, agent), do: write(agent, :append, &Memory.append(records, &1))
  @impl true
  def read(opts, agent), do: operation(agent, :read, &Memory.read(opts, &1))
  @impl true
  def latest_cursor(agent), do: operation(agent, :latest_cursor, &Memory.latest_cursor/1)
  @impl true
  def list_subscriptions(agent),
    do: operation(agent, :list_subscriptions, &Memory.list_subscriptions/1)

  @impl true
  def put_subscription(definition, agent),
    do: write(agent, :put_subscription, &Memory.put_subscription(definition, &1))

  @impl true
  def delete_subscription(id, agent),
    do: write(agent, :delete_subscription, &Memory.delete_subscription(id, &1))

  defp take(agent, callback) do
    Agent.get_and_update(agent, fn state ->
      {fault, faults} = Map.pop(state.faults, callback)

      {{fault, state.owner, state.token, state.gate},
       %{state | faults: faults, gate: if(callback == :append, do: false, else: state.gate)}}
    end)
  end

  defp operation(agent, callback, fun) do
    {fault, owner, token, _gate} = take(agent, callback)
    send(owner, {token, :store, callback})
    if fault, do: fault(fault), else: Agent.get(agent, &fun.(&1.memory))
  end

  defp write(agent, callback, fun) do
    {fault, owner, token, gate} = take(agent, callback)
    send(owner, {token, :store, callback})

    if gate do
      send(owner, {token, :append_held, self()})

      receive do
        {^token, :release_append} -> :ok
      end
    end

    if fault do
      fault(fault)
    else
      Agent.get_and_update(agent, fn state ->
        case fun.(state.memory) do
          {:ok, memory} -> {{:ok, agent}, %{state | memory: memory}}
          error -> {error, state}
        end
      end)
    end
  end

  defp fault("error"), do: {:error, :injected}
  defp fault("invalid"), do: :invalid_return
  defp fault("raise"), do: raise("store fault")
  defp fault("throw"), do: throw(:injected)
  defp fault("exit"), do: exit(:injected)
  defp fault("improper"), do: {:ok, [Model.record(1, "event.a") | :tail]}
  defp fault("bad-record"), do: {:ok, [nil]}
end
