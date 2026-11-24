defmodule Jido.Flow.DSL.CompileOrderTest do
  # Global call tracing observes the parallel compiler processes.
  use Covenant.Case, component: "jido_action.flow", async: false

  @moduletag :tmp_dir
  @moduletag obligation: "jido_action.flow.I7"

  test "a Flow waits for an advanced component target that compiles later", %{tmp_dir: dir} do
    suffix = System.unique_integer([:positive])
    action = Module.concat([Jido.Test, CompileOrder, "ItemAction#{suffix}"])
    flow = Module.concat([Jido.Test, CompileOrder, "MapFlow#{suffix}"])
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

    :erlang.trace_pattern({Code, :ensure_compiled!, 1}, [{[action], [], []}], [])
    :erlang.trace(:new_processes, true, [:call])

    on_exit(fn ->
      :erlang.trace(:new_processes, false, [:call])
      :erlang.trace_pattern({Code, :ensure_compiled!, 1}, false, [])
    end)

    task =
      Task.async(fn ->
        Kernel.ParallelCompiler.compile([action_file, flow_file], return_diagnostics: true)
      end)

    assert_receive {:action_waiting, action_compiler}, 5_000

    # The Flow compiler is now waiting for the Action instead of rejecting it.
    receive do
      {:trace, _pid, :call, {Code, :ensure_compiled!, [^action]}} -> :ok
      {ref, result} when ref == task.ref -> flunk("Flow compiled early: #{inspect(result)}")
    after
      5_000 -> flunk("Flow did not wait for its Map target")
    end

    send(action_compiler, :release)

    assert {:ok, modules, _diagnostics} = Task.await(task, 10_000)
    assert flow in modules
    assert Jido.Exec.run(flow, %{items: [1, 2]}) == {:ok, %{items: [%{item: 1}, %{item: 2}]}}
  end

  for {form, declaration} <- [
        {"keyword alias", ~s|map "each", collection: [1], action: Specialist.Request, params: %{item: item()}|},
        {"field-block module atom",
         """
         map "each" do
           collection [1]
           action TARGET
           params %{item: item()}
         end
         """}
      ] do
    @tag declaration: declaration
    test "an inline route Flow waits for its Map Action (#{form})", %{tmp_dir: dir, declaration: declaration} do
      namespace = Module.concat(__MODULE__, "Route#{System.unique_integer([:positive])}")
      coordinator = Module.concat(namespace, Coordinator)
      specialist = Module.concat(namespace, Specialist)
      action = Module.concat(specialist, Request)
      optional_action = Module.concat(specialist, OptionalAction)

      agent_file = Path.join(dir, "coordinator.ex")
      target_file = Path.join(dir, "specialist.ex")

      alias_line = if String.contains?(declaration, "Specialist.Request"), do: "alias #{inspect(specialist)}"
      declaration = String.replace(declaration, "TARGET", ":" <> inspect(Atom.to_string(action)))

      File.write!(agent_file, """
      defmodule #{inspect(coordinator)} do
        use Jido.Agent, name: "compile_order_coordinator"
        #{alias_line}

        routes do
          signal_source("/ordering")

          route "ordering.run" do
            flow schema: Jido.Joi.object(%{}) do
              #{declaration}
              output %{items: result("each")}
            end

            state(:unchanged)
            reply("ordering.done", from: output())
          end
        end
      end
      """)

      File.write!(target_file, """
      defmodule #{inspect(specialist)} do
        use Jido.Agent, name: "compile_order_specialist"
      end

      # Let the compiler release this optional lookup before it releases the Map target.
      Code.ensure_compiled(#{inspect(optional_action)})

      defmodule #{inspect(action)} do
        use Jido.Action, name: "compile_order_request"
        @impl true
        def run(params, _context), do: {:ok, params}
      end
      """)

      assert {:ok, modules, %{compile_warnings: [], runtime_warnings: []}} =
               Kernel.ParallelCompiler.compile([agent_file, target_file], return_diagnostics: true)

      assert coordinator in modules
      assert action in modules
      flow = coordinator.route_executable!("ordering.run")
      assert Jido.Exec.run(flow) == {:ok, %{items: [%{item: 1}]}}
    end
  end
end
