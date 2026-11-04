Code.require_file("../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.Durability.TelemetryTest do
  use ExUnit.Case, async: false
  @moduletag :example

  setup_all do
    JidoTest.Examples.Loader.require_source!("05_flow_durability/05_06_telemetry/telemetry.ex")

    :ok
  end

  test "correlates managed workflow and Action telemetry" do
    events = [
      [:jido, :action, :start],
      [:jido, :action, :stop],
      [:runic, :runner, :workflow, :start],
      [:runic, :runner, :workflow, :stop],
      [:runic, :runner, :runnable, :start],
      [:runic, :runner, :runnable, :stop]
    ]

    token = make_ref()
    handler = {__MODULE__, token}
    :ok = :telemetry.attach_many(handler, events, &__MODULE__.handle_event/4, {self(), token})
    on_exit(fn -> :telemetry.detach(handler) end)

    runner = Module.concat(__MODULE__, Runner)
    start_supervised!({Runic.Runner, name: runner})
    id = {:telemetry, System.unique_integer([:positive])}
    owner = self()

    assert {:ok, _worker} =
             Jido.Exec.start(
               runner,
               id,
               Jido.Examples.Durability.Telemetry,
               %{value: 4},
               %{},
               hooks: [on_idle: fn _state -> send(owner, :idle) end]
             )

    assert_receive :idle, 1_000
    assert_receive {^token, [:jido, :action, :start], _, %{runnable_id: runnable_id}}, 1_000
    assert_receive {^token, [:jido, :action, :stop], _, %{runnable_id: ^runnable_id}}, 1_000
    assert_receive {^token, [:runic, :runner, :workflow, :start], _, %{id: ^id}}, 1_000
    assert_receive {^token, [:runic, :runner, :workflow, :stop], _, %{id: ^id}}, 1_000
    assert_receive {^token, [:runic, :runner, :runnable, :start], _, %{runnable_id: ^runnable_id}}, 1_000
    assert_receive {^token, [:runic, :runner, :runnable, :stop], _, %{runnable_id: ^runnable_id}}, 1_000
    assert Jido.Exec.result(runner, id) == {:ok, %{value: 5}}
  end

  def handle_event(event, measurements, metadata, {test_pid, token}) do
    send(test_pid, {token, event, measurements, metadata})
  end
end
