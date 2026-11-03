Code.require_file("support/fuzz.exs", __DIR__)
Code.require_file("support/runtime.exs", __DIR__)

defmodule JidoTest.Property.Signal.PidLifecyclesTest do
  use ExUnit.Case, async: true
  import StreamData
  alias Jido.Signal
  alias Jido.Signal.Dispatch
  alias JidoTest.Property.Signal.{Fuzz, Runtime}

  for {suite, runs} <- [property: 40, fuzz: 500] do
    @tag [
      {suite, true},
      max_runs: runs,
      max_run_time: if(suite == :fuzz, do: 300_000, else: 10_000),
      timeout: if(suite == :fuzz, do: 900_000, else: 90_000)
    ]
    @tag contracts: ["DISP-002"]
    @tag contract_cases: [
           "DISP-002/live-dead-remote-self",
           "DISP-002/held-sync",
           "DISP-002/timeout-ceiling",
           "DISP-002/async-message"
         ]
    test "#{suite}: PID delivery follows process lifecycle", context do
      generator =
        fixed_map(%{
          "reply" => member_of(~w(ok error)),
          "timeout" => member_of([1, 10, 5000, 4_294_967_295])
        })

      examples =
        for reply <- ~w(ok error),
            timeout <- [1, 4_294_967_295],
            do: %{"reply" => reply, "timeout" => timeout}

      Fuzz.check(
        "pid_lifecycles",
        generator,
        Map.to_list(context) ++ [examples: examples],
        &check/1
      )
    end
  end

  defp check(%{"reply" => reply, "timeout" => timeout}) do
    owner = self()
    token = make_ref()
    signal = Signal.new!("pid.event", %{"_probe" => token}, source: "/property")
    assert :ok = Dispatch.dispatch(signal, {:pid, [target: owner]})
    assert_received {:signal, ^signal}

    assert {:error, {:calling_self, _}} =
             Dispatch.dispatch(signal, {:pid, [target: owner, delivery_mode: :sync]})

    assert {:error, _} =
             Dispatch.validate_opts({:pid, [target: JidoSignalTest.Case.remote_pid()]})

    for invalid <- [0, -1, 4_294_967_296, "1000"],
        do: assert(match?({:error, _}, Dispatch.validate_opts({:pid, [target: owner, timeout: invalid]})))

    target =
      spawn_link(fn ->
        monitor = Process.monitor(owner)
        send(owner, {token, :ready, self()})

        receive do
          {:"$gen_call", from, {:signal, ^signal}} ->
            send(owner, {token, :held, self()})

            receive do
              {^token, :release} ->
                GenServer.reply(
                  from,
                  if(reply == "error", do: {:error, :receiver_error}, else: :accepted)
                )

              {:DOWN, ^monitor, :process, ^owner, _} ->
                :ok
            end

          {:DOWN, ^monitor, :process, ^owner, _} ->
            :ok
        end
      end)

    ref = Process.monitor(target)
    assert_receive {^token, :ready, ^target}, 5_000
    # Hold the call with a long timeout, then release by a message. No scheduler-time assertion.
    task =
      Task.async(fn ->
        Dispatch.dispatch(signal, {:pid, [target: target, delivery_mode: :sync, timeout: 5000]})
      end)

    try do
      assert_receive {^token, :held, ^target}, 5_000
      assert Task.yield(task, 0) == nil
      send(target, {token, :release})
      expected = if reply == "error", do: {:error, :receiver_error}, else: :ok
      assert Task.await(task) == expected
      assert_receive {:DOWN, ^ref, :process, ^target, :normal}, 5_000

      assert {:error, :process_not_alive} =
               Dispatch.dispatch(signal, {:pid, [target: target, timeout: timeout]})

      assert {:ok, _} = Dispatch.validate_opts({:pid, [target: owner, timeout: timeout]})
    after
      if Process.alive?(task.pid), do: Task.shutdown(task, :brutal_kill)

      if Process.alive?(target) do
        Process.unlink(target)
        Process.exit(target, :kill)
      end

      Process.demonitor(ref, [:flush])
      Runtime.drain(token)
    end

    ["reply-#{reply}", "timeout-#{timeout}"]
  end
end
