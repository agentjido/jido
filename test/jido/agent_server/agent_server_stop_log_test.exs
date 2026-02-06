defmodule JidoTest.AgentServerStopLogTest do
  use JidoTest.Case, async: false

  import ExUnit.CaptureLog

  alias Jido.Agent.Directive
  alias Jido.AgentServer
  alias Jido.Signal

  defmodule StopTestAction do
    @moduledoc false
    use Jido.Action, name: "stop_test", schema: []

    def run(_params, _context) do
      {:ok, %{}, [%Directive.Stop{reason: :normal}]}
    end
  end

  defmodule TestAgent do
    @moduledoc false
    use Jido.Agent, name: "test_agent", schema: []

    def signal_routes(_ctx) do
      [{"stop_test", StopTestAction}]
    end
  end

  setup do
    previous_level = Logger.level()
    Logger.configure(level: :warning)

    on_exit(fn ->
      Logger.configure(level: previous_level)
    end)

    :ok
  end

  test "Stop directive with normal reason logs warning", %{jido: jido} do
    log =
      capture_log(fn ->
        {:ok, pid} = AgentServer.start_link(agent: TestAgent, jido: jido)
        ref = Process.monitor(pid)

        signal = Signal.new!("stop_test", %{}, source: "/test")
        AgentServer.cast(pid, signal)

        assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
      end)

    assert log =~ "received {:stop, :normal"
    assert log =~ "This is a HARD STOP"
  end
end
