defmodule Jido.Flow.DSL.CompileOrderTest do
  # Global call tracing observes the parallel compiler processes.
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  test "a Flow waits for an advanced component target that compiles later", %{tmp_dir: dir} do
    suffix = System.unique_integer([:positive])
    action = Module.concat([JidoActionTest, CompileOrder, "ItemAction#{suffix}"])
    flow = Module.concat([JidoActionTest, CompileOrder, "MapFlow#{suffix}"])
    test_pid = :erlang.pid_to_list(self())

    action_file = Path.join(dir, "action.ex")
    flow_file = Path.join(dir, "flow.ex")

    File.write!(action_file, """
    send(:erlang.list_to_pid(#{inspect(test_pid)}), {:action_waiting, self()})
    receive do: (:release -> :ok)

    defmodule #{inspect(action)} do
      use Jido.Action, name: "compile_order_item"
      @impl true
      def run(params, _context), do: {:ok, params}
    end
    """)

    File.write!(flow_file, """
    defmodule #{inspect(flow)} do
      use Jido.Flow, name: "compile_order_map"

      flow do
        map "each", collection: input(:items), action: #{inspect(action)}, params: %{item: item()}
        output %{items: result("each")}
      end
    end
    """)

    :erlang.trace_pattern({Code, :ensure_compiled, 1}, [{[action], [], []}], [])
    :erlang.trace(:new_processes, true, [:call])

    on_exit(fn ->
      :erlang.trace(:new_processes, false, [:call])
      :erlang.trace_pattern({Code, :ensure_compiled, 1}, false, [])
    end)

    task =
      Task.async(fn ->
        Kernel.ParallelCompiler.compile([action_file, flow_file], return_diagnostics: true)
      end)

    assert_receive {:action_waiting, action_compiler}, 5_000

    # The Flow compiler is now waiting for the Action instead of rejecting it.
    receive do
      {:trace, _pid, :call, {Code, :ensure_compiled, [^action]}} -> :ok
      {ref, result} when ref == task.ref -> flunk("Flow compiled early: #{inspect(result)}")
    after
      5_000 -> flunk("Flow did not wait for its Map target")
    end

    send(action_compiler, :release)

    assert {:ok, modules, _diagnostics} = Task.await(task, 10_000)
    assert flow in modules
    assert Jido.Exec.run(flow, %{items: [1, 2]}) == {:ok, %{items: [%{item: 1}, %{item: 2}]}}
  end
end
