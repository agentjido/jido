defmodule Jido.Plugin.Scheduler.DeliveryTest do
  use ExUnit.Case, async: true

  alias Jido.Plugin.Scheduler
  alias Jido.Plugin.Scheduler.Delivery
  alias Jido.Signal

  test "attempt delivers one pending job and rotates in stable job order" do
    state = pending_state([:third, :first, :second])

    assert {:delivered, {:after, :first}, {:ok, :first}} =
             attempt(state, :start, {:ok, :first})

    assert {:delivered, {:after, :second}, {:ok, :second}} =
             attempt(state, {:after, :first}, {:ok, :second})

    assert {:delivered, {:after, :third}, {:ok, :third}} =
             attempt(state, {:after, :second}, {:ok, :third})

    assert {:delivered, {:after, :first}, {:ok, :wrapped}} =
             attempt(state, {:after, :third}, {:ok, :wrapped})
  end

  test "attempt rotates after a nil job ID" do
    state = pending_state([nil, "second"])

    assert {:delivered, {:after, nil}, {:ok, :nil_job}} =
             attempt(state, :start, {:ok, :nil_job})

    assert {:delivered, {:after, "second"}, {:ok, :string_job}} =
             attempt(state, {:after, nil}, {:ok, :string_job})

    assert {:delivered, {:after, nil}, {:ok, :wrapped}} =
             attempt(state, {:after, "second"}, {:ok, :wrapped})
  end

  test "attempt returns typed Agent delivery errors with the selected cursor" do
    state = pending_state([:first, :second])

    assert {:error, {:after, :first}, {:delivery_failed, :rejected}} =
             attempt(state, :start, {:error, :rejected})

    assert {:error, {:after, :second}, {:delivery_failed, :timed_out}} =
             attempt(state, {:after, :first}, {:error, :timed_out})
  end

  test "attempt distinguishes idle state from state-read failures" do
    assert {:idle, :start} = plugin_state_result(:start, {:ok, %{cron: %{}}})

    assert {:error, {:after, :first}, {:state_read_failed, :not_ready}} =
             plugin_state_result({:after, :first}, {:error, :not_ready})

    assert {:error, {:after, :first}, {:invalid_scheduler_state, nil}} =
             plugin_state_result({:after, :first}, {:ok, nil})

    dead = spawn(fn -> :ok end)
    monitor = Process.monitor(dead)
    assert_receive {:DOWN, ^monitor, :process, ^dead, reason}
    assert reason in [:normal, :noproc]

    assert {:error, {:after, :first}, {:state_read_unavailable, _reason}} =
             Delivery.attempt(dead, {:after, :first}, 10)
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

    assert {:error, {:after, :first}, {:delivery_unavailable, _reason}} =
             Delivery.attempt(server, :start, 1_000)

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

    Task.await(task)
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
