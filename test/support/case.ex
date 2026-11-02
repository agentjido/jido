defmodule JidoActionTest.Case do
  @moduledoc """
  Test case helper module providing common test functionality for Jido tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import JidoActionTest.Case
    end
  end

  @doc """
  Creates a unique module name under the calling test module.
  """
  defmacro unique_module(prefix) do
    namespace = __CALLER__.module

    quote bind_quoted: [namespace: namespace, prefix: prefix] do
      Module.concat(namespace, :"#{prefix}#{System.unique_integer([:positive])}")
    end
  end

  @doc """
  Creates a runtime module and asserts that compilation succeeded.
  """
  def create_module(module, quoted) do
    assert {:module, ^module, _bytecode, _term} =
             Module.create(module, quoted, Macro.Env.location(__ENV__))
  end

  @doc """
  Runs a function in a monitored process and returns its result.

  Use `assert_mailbox_empty: true` when the caller process must not retain
  messages after the function returns.
  """
  def run_in_monitored_caller(fun, opts \\ []) when is_function(fun, 0) do
    owner = self()
    ref = make_ref()

    {caller, monitor} =
      spawn_monitor(fn ->
        result = fun.()
        {:messages, messages} = Process.info(self(), :messages)
        send(owner, {ref, result, messages})
      end)

    assert_receive {^ref, result, messages}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^caller, :normal}, 1_000

    if Keyword.get(opts, :assert_mailbox_empty, false) do
      assert messages == []
    end

    result
  end
end
