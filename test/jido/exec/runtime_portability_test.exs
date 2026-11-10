defmodule Jido.Exec.RuntimePortabilityTest do
  use Covenant.Case, component: "jido_action.boundary", async: false

  alias Jido.Exec
  alias Jido.Flow
  alias Jido.Flow.Ref

  defmodule UnprojectedData do
    defstruct value: 1
  end

  defmodule BlockingAction do
    use Jido.Action, name: "exec_v2_portable_blocking"

    @impl true
    def run(_params, _context) do
      receive do
        :release -> {:ok, %{released: true}}
      end
    end
  end

  defmodule LocalOutputAction do
    use Jido.Action, name: "exec_v2_local_output"

    @impl true
    def run(_params, _context), do: {:ok, %{pid: self()}}
  end

  defmodule EchoInput do
    use Jido.Action, name: "exec_v2_echo_local_input"

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  @tag obligation: "jido_action.boundary.I10"
  test "managed execution rejects process-local input before it starts" do
    runner = start_runner!()
    execution_id = unique_id()

    assert {:error, error} = Exec.start(runner, execution_id, BlockingAction, %{}, %{pid: self()})
    assert error.details.reason == :non_portable_durable_value
    assert error.details.type == :pid
    assert Runic.Runner.lookup(runner, execution_id) == nil
  end

  @tag obligation: "jido_action.boundary.I10"
  test "managed execution fails a process-local Action result before persistence" do
    runner = start_runner!()
    execution_id = unique_id()
    test_pid = self()

    assert {:ok, _worker} =
             Exec.start(runner, execution_id, LocalOutputAction, %{}, %{},
               hooks: [
                 on_failed: fn _runnable, error, _state ->
                   send(test_pid, {:local_output_failed, error})
                 end
               ]
             )

    assert_receive {:local_output_failed, error}, 1_000
    assert error.details.reason == :non_portable_durable_value
    assert error.details.type == :pid
  end

  @tag obligation: "jido_action.boundary.I10"
  test "managed input accepts a safe local struct without canonical expansion" do
    runner = start_runner!()
    id = unique_id()
    flow = input_flow()
    owner = self()

    assert {:ok, _worker} =
             Exec.start(runner, id, flow, %{value: %UnprojectedData{}}, %{},
               hooks: [on_idle: fn _state -> send(owner, :local_input_idle) end]
             )

    assert_receive :local_input_idle
    assert Exec.result(runner, id) == {:ok, %{value: %UnprojectedData{}}}
  end

  @tag obligation: "jido_action.boundary.I10"
  test "a duplicate start leaves the existing Worker intact" do
    runner = start_runner!()
    id = unique_id()
    flow = input_flow()
    assert {:ok, worker} = Exec.start(runner, id, flow, %{value: 1}, %{}, dispatch_mode: :manual)

    assert {:error, %{details: %{reason: {:already_started, ^worker}}}} =
             Exec.start(runner, id, flow, %{value: %UnprojectedData{}})

    assert Runic.Runner.lookup(runner, id) == worker
    assert Process.alive?(worker)
  end

  defp input_flow do
    Flow.new!(%{
      name: "portable_input",
      components: [
        %{kind: :step, name: "echo", action: EchoInput, params: %{value: Ref.input(:value)}}
      ],
      output: Ref.result("echo")
    })
  end

  defp start_runner! do
    runner = __MODULE__.Runner
    start_supervised!({Runic.Runner, name: runner})
    runner
  end

  defp unique_id, do: {:exec_v2_portable, System.unique_integer([:positive])}
end
