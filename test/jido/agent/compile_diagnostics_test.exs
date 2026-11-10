defmodule Jido.Agent.CompileDiagnosticsTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir
  @timeout 30_000

  # A cycle used to hang the compiler, so the timeout makes a regression fail.
  defp compile_failure(tmp_dir, source) do
    file = Path.join(tmp_dir, "agent.ex")
    File.write!(file, source)

    {pid, ref} =
      spawn_monitor(fn ->
        exit({:returned, Kernel.ParallelCompiler.compile([file], return_diagnostics: true)})
      end)

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      ExUnit.CaptureLog.capture_log(fn ->
        send(self(), {:result, wait(pid, ref)})
      end)
    end)

    assert_received {:result, result}
    {file, result}
  end

  defp wait(pid, ref) do
    receive do
      {:DOWN, ^ref, :process, ^pid, reason} -> reason
    after
      @timeout ->
        Process.exit(pid, :kill)
        flunk("Agent compilation did not finish")
    end
  end

  defp suffix, do: System.unique_integer([:positive])

  test "a module that lists itself reports recursive_membership with a location", %{tmp_dir: tmp_dir} do
    module = "Jido.Test.SelfMember#{suffix()}"

    {file, result} =
      compile_failure(tmp_dir, """
      defmodule #{module} do
        use Jido.Agent, name: "self_member"

        topology do
          agent :me, #{module}
        end
      end
      """)

    assert {%CompileError{file: ^file, line: line} = error, _stack} = result
    assert line == 1
    assert Exception.message(error) =~ ":recursive_membership"
    assert Exception.message(error) =~ "cannot be cyclic"
  end

  test "two modules that list each other report recursive_membership with a location", %{tmp_dir: tmp_dir} do
    id = suffix()

    {file, result} =
      compile_failure(tmp_dir, """
      defmodule Jido.Test.CycleA#{id} do
        use Jido.Agent, name: "cycle_a"

        topology do
          agent :b, Jido.Test.CycleB#{id}
        end
      end

      defmodule Jido.Test.CycleB#{id} do
        use Jido.Agent, name: "cycle_b"

        topology do
          agent :a, Jido.Test.CycleA#{id}
        end
      end
      """)

    assert {%CompileError{file: ^file, line: line} = error, _stack} = result
    assert line in [1, 9]
    assert Exception.message(error) =~ ":recursive_membership"
  end

  test "a selector on a target with no field schema names output_schema and the location", %{tmp_dir: tmp_dir} do
    id = suffix()

    {file, result} =
      compile_failure(tmp_dir, """
      defmodule Jido.Test.NoOutputAction#{id} do
        use Jido.Action, name: "no_output_action"
        def run(_params, _context), do: {:ok, %{}}
      end

      defmodule Jido.Test.NoOutputAgent#{id} do
        use Jido.Agent, name: "no_output_agent"

        routes do
          signal_source "/test"

          route "test.selected", Jido.Test.NoOutputAction#{id} do
            state from: output(:field)
          end
        end
      end
      """)

    assert {%CompileError{file: ^file, line: 6} = error, _stack} = result
    assert Exception.message(error) =~ "output_schema"
    assert Exception.message(error) =~ ":unsupported_output_path"
  end

  test "a selector on an undeclared field names output_schema and the location", %{tmp_dir: tmp_dir} do
    id = suffix()

    {file, result} =
      compile_failure(tmp_dir, """
      defmodule Jido.Test.DeclaredOutputAction#{id} do
        use Jido.Action,
          name: "declared_output_action",
          output_schema: Jido.Joi.object(%{value: Jido.Joi.integer()})

        def run(_params, _context), do: {:ok, %{value: 1}}
      end

      defmodule Jido.Test.DeclaredOutputAgent#{id} do
        use Jido.Agent, name: "declared_output_agent"

        routes do
          signal_source "/test"

          route "test.selected", Jido.Test.DeclaredOutputAction#{id} do
            state from: output(:missing)
          end
        end
      end
      """)

    assert {%CompileError{file: ^file, line: 9} = error, _stack} = result
    assert Exception.message(error) =~ "output_schema"
    assert Exception.message(error) =~ ":unknown_output_field"
  end

  test "a repeated member that is not a cycle still compiles", %{tmp_dir: tmp_dir} do
    id = suffix()

    {_file, result} =
      compile_failure(tmp_dir, """
      defmodule Jido.Test.Leaf#{id} do
        use Jido.Agent, name: "leaf"
      end

      defmodule Jido.Test.Middle#{id} do
        use Jido.Agent, name: "middle"

        topology do
          agent :leaf, Jido.Test.Leaf#{id}
        end
      end

      defmodule Jido.Test.Top#{id} do
        use Jido.Agent, name: "top"

        topology do
          agent :left, Jido.Test.Middle#{id}
          agent :right, Jido.Test.Middle#{id}
          agent :leaf, Jido.Test.Leaf#{id}
        end
      end
      """)

    assert {:returned, {:ok, modules, _info}} = result
    assert Module.concat([Jido, Test, "Top#{id}"]) in modules
  end
end
