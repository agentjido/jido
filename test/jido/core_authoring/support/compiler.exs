defmodule JidoTest.Authoring.Compiler do
  @moduledoc false
  import ExUnit.Assertions

  def require_file!(path) do
    {_, diagnostics} = run(fn -> Code.require_file(path) end)
    assert diagnostics == [], "Unexpected diagnostics in #{path}: #{inspect(diagnostics)}"
    :ok
  end

  def compile_file(path), do: run(fn -> Code.compile_file(path) end)

  # after_verify failures can arrive through a linked checker after the compile
  # call returns. Wait for compiler exit, then preserve the original exception.
  # This isolates a compiler process, not the VM's module table.
  def run(fun) do
    owner = self()

    {pid, ref} =
      spawn_monitor(fn ->
        result = Code.with_diagnostics([log: false], fun)
        send(owner, {self(), :compiled, result})
      end)

    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} ->
        assert_receive {^pid, :compiled, result}
        result

      {:DOWN, ^ref, :process, ^pid, {error, stack}} when is_exception(error) ->
        reraise error, stack

      {:DOWN, ^ref, :process, ^pid, reason} ->
        flunk("Compiler exited: #{inspect(reason)}")
    after
      10_000 ->
        Process.exit(pid, :kill)
        assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
        flunk("Compiler did not finish within 10 seconds")
    end
  end
end
