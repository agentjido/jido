defmodule Jido.Plugin.Scheduler.DeliveryTest do
  use ExUnit.Case, async: true

  alias Jido.Plugin.Scheduler
  alias Jido.Plugin.Scheduler.Delivery
  alias Jido.Signal

  test "attempt delivers one pending job and rotates in stable job order" do
    state = pending_state([:third, :first, :second])

    assert {:first, {:ok, :first}} = attempt(state, nil, {:ok, :first})
    assert {:second, {:ok, :second}} = attempt(state, :first, {:ok, :second})
    assert {:third, {:ok, :third}} = attempt(state, :second, {:ok, :third})
    assert {:first, {:ok, :wrapped}} = attempt(state, :third, {:ok, :wrapped})
  end

  test "attempt keeps the selected cursor for Agent errors" do
    state = pending_state([:first, :second])

    assert {:first, {:error, :rejected}} = attempt(state, nil, {:error, :rejected})

    assert {:second, {:error, :timed_out}} =
             attempt(state, :first, {:error, :timed_out})
  end

  test "attempt keeps the cursor while Plugin state is missing or unavailable" do
    assert {nil, :idle} = plugin_state_result(nil, {:ok, %{cron: %{}}})
    assert {:first, :idle} = plugin_state_result(:first, {:error, :not_ready})

    dead = spawn(fn -> :ok end)
    monitor = Process.monitor(dead)
    assert_receive {:DOWN, ^monitor, :process, ^dead, reason}
    assert reason in [:normal, :noproc]

    assert {:first, {:error, {:occurrence_delivery_unavailable, _reason}}} =
             Delivery.attempt(dead, :first, 10)
  end

  test "attempt contains Agent exit after it selects a job" do
    state = pending_state([:first])
    owner = self()

    server =
      spawn(fn ->
        receive do
          {:"$gen_call", from, {:plugin_state, Scheduler}} ->
            :gen_statem.reply(from, {:ok, state})
        end

        receive do
          {:"$gen_call", _from, {:signal, _ref, _signal, _deadline, %{}}} ->
            send(owner, :agent_call_received)
            exit(:simulated_agent_loss)
        end
      end)

    assert {:first, {:error, {:occurrence_delivery_unavailable, _reason}}} =
             Delivery.attempt(server, nil, 1_000)

    assert_received :agent_call_received
  end

  defp attempt(state, previous_job, response) do
    server = self()
    task = Task.async(fn -> Delivery.attempt(server, previous_job, 1_000) end)

    assert_receive {:"$gen_call", plugin_from, {:plugin_state, Scheduler}}, 1_000
    :gen_statem.reply(plugin_from, {:ok, state})

    assert_receive {:"$gen_call", agent_from, {:signal, _ref, delivered, _deadline, %{}}},
                   1_000

    {_job, %{pending: original}} =
      Enum.find(state.cron, fn {_job, spec} -> spec.pending.type == delivered.type end)

    refute delivered.id == original.id
    assert delivered.type == original.type
    assert delivered.data == original.data
    :gen_statem.reply(agent_from, response)

    {selected, result} = Task.await(task)
    {selected, result}
  end

  defp plugin_state_result(previous_job, response) do
    server = self()
    task = Task.async(fn -> Delivery.attempt(server, previous_job, 1_000) end)
    assert_receive {:"$gen_call", from, {:plugin_state, Scheduler}}, 1_000
    :gen_statem.reply(from, response)
    Task.await(task)
  end

  defp pending_state(jobs) do
    cron =
      Map.new(jobs, fn job ->
        signal = Signal.new!("scheduler.#{job}", %{job: job}, source: "/test")
        {job, %{delivery: :durable, pending: signal}}
      end)

    %{cron: cron}
  end
end
