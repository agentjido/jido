defmodule JidoTest.AgentServer.SignalCallDrainRaceTest do
  use JidoTest.Case, async: true

  @moduletag :capture_log

  alias Jido.Agent.Directive
  alias Jido.AgentServer
  alias Jido.Signal

  defmodule SlowCallAction do
    @moduledoc false
    use Jido.Action, name: "race_slow_call"

    def run(_params, %{state: %{test_pid: test_pid}}) when is_pid(test_pid) do
      send(test_pid, {:slow_call_started, self()})

      receive do
        :release_slow_call -> {:ok, %{call_done: true}}
      after
        1_000 -> {:error, :slow_call_not_released}
      end
    end
  end

  defmodule RuntimeMutationAction do
    @moduledoc false
    use Jido.Action, name: "race_runtime_mutation"

    def run(_params, %{state: %{test_pid: test_pid}}) when is_pid(test_pid) do
      send(test_pid, :runtime_instruction_ran)
      {:ok, %{runtime_done: true}}
    end
  end

  defmodule CaptureRuntimeResultAction do
    @moduledoc false
    use Jido.Action, name: "race_capture_runtime_result"

    def run(%{status: :ok, result: result}, _context) do
      {:ok, %{runtime_done: Map.get(result, :runtime_done), instruction_seen: true}}
    end
  end

  defmodule QueueRuntimeInstructionAction do
    @moduledoc false
    use Jido.Action, name: "race_queue_runtime_instruction"

    def run(_params, _context) do
      instruction = Jido.Instruction.new!(%{action: RuntimeMutationAction})

      directive =
        Directive.run_instruction(instruction, result_action: CaptureRuntimeResultAction)

      {:ok, %{}, [directive]}
    end
  end

  defmodule RaceAgent do
    @moduledoc false
    use Jido.Agent,
      name: "signal_call_drain_race_agent",
      schema: [
        test_pid: [type: :any, default: nil],
        call_done: [type: :boolean, default: false],
        runtime_done: [type: :boolean, default: false],
        instruction_seen: [type: :boolean, default: false]
      ]

    def signal_routes(_ctx) do
      [
        {"queue_runtime_instruction", QueueRuntimeInstructionAction},
        {"slow_call", SlowCallAction}
      ]
    end
  end

  test "sync call result preserves state committed by the drain loop", %{jido: jido} do
    {:ok, pid} =
      AgentServer.start_link(
        agent: RaceAgent,
        id: unique_id("drain-race"),
        initial_state: %{test_pid: self()},
        jido: jido
      )

    on_exit(fn ->
      if Process.alive?(pid) do
        try do
          :sys.resume(pid)
        catch
          :exit, _ -> :ok
        end

        try do
          GenServer.stop(pid)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    :ok = :sys.suspend(pid)
    :ok = AgentServer.cast(pid, signal("queue_runtime_instruction"))

    call_task =
      Task.async(fn ->
        AgentServer.call(pid, signal("slow_call"), 2_000)
      end)

    eventually(fn -> queued_cast_and_call?(pid) end)

    :ok = :sys.resume(pid)

    assert_receive {:slow_call_started, call_runner}, 500

    send(call_runner, :release_slow_call)

    assert {:ok, returned_agent} = Task.await(call_task, 2_000)
    assert returned_agent.state.call_done == true
    assert_receive :runtime_instruction_ran, 500

    eventually_state(pid, fn state ->
      state.agent.state.call_done == true and state.agent.state.runtime_done == true and
        state.agent.state.instruction_seen == true
    end)
  end

  defp queued_cast_and_call?(pid) do
    case Process.info(pid, :messages) do
      {:messages, messages} ->
        Enum.any?(messages, &queue_runtime_instruction_cast?/1) and
          Enum.any?(messages, &slow_call?/1)

      nil ->
        false
    end
  end

  defp queue_runtime_instruction_cast?(
         {:"$gen_cast", {:signal, %Signal{type: "queue_runtime_instruction"}}}
       ),
       do: true

  defp queue_runtime_instruction_cast?(_message), do: false

  defp slow_call?({:"$gen_call", _from, {:signal, %Signal{type: "slow_call"}}}), do: true
  defp slow_call?(_message), do: false
end
