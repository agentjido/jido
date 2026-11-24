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

  test "an invalid Signal source reports its field at compile time", %{tmp_dir: tmp_dir} do
    module = "Jido.Test.InvalidSignalSource#{suffix()}"

    {file, result} =
      compile_failure(tmp_dir, """
      defmodule #{module} do
        use Jido.Agent, name: "bad_signal_source"

        routes do
          signal_source "not a URI"
        end
      end
      """)

    {^file, line, message} = diagnostic(result)
    assert is_integer(line) and line > 0
    assert message =~ "signal_source"
    assert message =~ "URI-reference"
  end

  test "DSL diagnostics include the provider and cause of a failed authoring callback", %{tmp_dir: tmp_dir} do
    for {name, body, callback, reason} <- [
          {"BadId", ~s|use Jido.Plugin, id: raise("ID failed")|, ":id", "ID failed"},
          {"BadLower", ~s|use Jido.Plugin, id: "bad-lower"\ndef lower(_, _), do: throw(:bad_data)|, ":lower",
           ":bad_data"},
          {"BadVerify", ~s|use Jido.Plugin, id: "bad-verify"\ndef verify(_, _), do: raise("verification failed")|,
           ":verify", "verification failed"},
          {"InvalidVerify", ~s|use Jido.Plugin, id: "invalid-verify"\ndef verify(_, _), do: :unexpected|, ":verify",
           ":unexpected"}
        ] do
      id = suffix()
      plugin = "Jido.Test.#{name}#{id}"

      {file, result} =
        compile_failure(tmp_dir, """
        defmodule #{plugin} do
          #{body}
        end

        defmodule Jido.Test.FaultyAuthoring#{id} do
          use Jido.Agent, name: "faulty_authoring", plugins: [#{plugin}]
        end
        """)

      {^file, line, message} = diagnostic(result)
      assert is_integer(line) and line > 0
      assert message =~ plugin
      assert message =~ reason
      assert message =~ callback
    end
  end

  defp diagnostic({:returned, {:error, [diagnostic], _info}}) do
    line =
      case diagnostic.position do
        {line, _column} when line > 0 -> line
        line when is_integer(line) and line > 0 -> line
        _ -> diagnostic_source_line(diagnostic)
      end

    {diagnostic.file, line, diagnostic.message}
  end

  defp diagnostic({%CompileError{} = error, _stack}),
    do: {error.file, error.line, Exception.message(error)}

  defp diagnostic_source_line(diagnostic) do
    path = Regex.escape(Path.relative_to_cwd(diagnostic.file))
    [line] = Regex.run(~r/#{path}:(\d+)/, diagnostic.message, capture: :all_but_first)
    String.to_integer(line)
  end

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

  @tag obligation: "jido.agent.I4"
  test "an inline output projection uses the current declaration before the Agent is emitted", %{
    tmp_dir: tmp_dir
  } do
    module = Module.concat(Jido.Test, "InlineOutputRetry#{suffix()}")

    source = """
    defmodule #{inspect(module)} do
      use Jido.Agent, name: "inline_output_retry"

      routes do
        signal_source "/test"

        route "test.project" do
          action _params do
            {:ok, %{state: %{}, reply: %{}}}
          end

          state from: output("state")
          reply "test.project.done", from: output("reply")
        end
      end
    end
    """

    {file, result} = compile_failure(tmp_dir, source)
    assert {^file, 1, message} = diagnostic(result)
    assert message =~ ":unsupported_output_path"
    assert message =~ "[:routes, 0, :state, :path, 0]"
    refute Code.loaded?(module)

    corrected =
      String.replace(
        source,
        "action _params do",
        "action _params, output_schema: Jido.Joi.object(%{state: Jido.Joi.object(%{}), reply: Jido.Joi.object(%{})}) do"
      )

    File.write!(file, corrected)
    assert {:ok, _modules, _info} = Kernel.ParallelCompiler.compile([file], return_diagnostics: true)

    assert %{routes: [%{state: %{path: [:state]}, reply: %{from: %{path: [:reply]}}}]} =
             module.definition()
  end

  @tag obligation: "jido.agent.I4"
  test "a declared reply requires a Signal source before the Agent is emitted", %{tmp_dir: tmp_dir} do
    module = Module.concat(Jido.Test, "ReplySourceRetry#{suffix()}")

    source = """
    defmodule #{inspect(module)} do
      use Jido.Agent, name: "reply_source_retry"

      routes do
        route "test.reply" do
          action _params do
            {:ok, %{}}
          end

          state :unchanged
          reply "test.reply.done", from: output()
        end
      end
    end
    """

    {file, result} = compile_failure(tmp_dir, source)
    assert {^file, 1, message} = diagnostic(result)
    assert message =~ ":reply_source_required"
    assert message =~ "[:signal_source]"
    refute Code.loaded?(module)

    File.write!(file, String.replace(source, "routes do", "routes do\n    signal_source \"/test\""))
    assert {:ok, _modules, _info} = Kernel.ParallelCompiler.compile([file], return_diagnostics: true)
    assert %{signal_source: "/test", routes: [%{reply: %{type: "test.reply.done"}}]} = module.definition()
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
