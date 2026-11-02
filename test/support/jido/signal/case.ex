defmodule JidoSignalTest.Case do
  @moduledoc false

  use ExUnit.CaseTemplate

  import ExUnit.Assertions

  using do
    quote do
      import JidoSignalTest.Case
      import JidoSignalTest.Fixtures.Signals
    end
  end

  def unique_name(prefix) when is_binary(prefix) do
    "#{prefix}_#{System.unique_integer([:positive])}"
  end

  # An external PID value, without starting or connecting to a remote node.
  def remote_pid do
    <<131, node_term::binary>> = :erlang.term_to_binary(:signal_test_remote@host)
    :erlang.binary_to_term(<<131, 103>> <> node_term <> <<1::32, 0::32, 0>>, [:safe])
  end

  defmacro unique_module(prefix) do
    namespace = __CALLER__.module

    quote bind_quoted: [namespace: namespace, prefix: prefix] do
      Module.concat(namespace, :"#{prefix}#{System.unique_integer([:positive])}")
    end
  end

  def create_module(module, quoted) do
    assert {:module, ^module, _bytecode, _term} =
             Module.create(module, quoted, Macro.Env.location(__ENV__))
  end

  def terminate_and_wait(server, target) when is_pid(server) and is_pid(target) do
    monitor = Process.monitor(target)
    :erlang.trace(server, true, [:receive])

    try do
      Process.exit(target, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^target, :killed}, 1_000

      assert_receive {:trace, ^server, :receive, {:DOWN, _ref, :process, ^target, :killed}},
                     1_000

      :sys.get_state(server)
      :ok
    after
      :erlang.trace(server, false, [:receive])
      Process.demonitor(monitor, [:flush])
    end
  end
end
