defmodule JidoTest.Case do
  @moduledoc """
  Test case helper module providing common test functionality for Jido tests.

  Includes agent DSL functionality for testing agent workflows.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import test helpers
      import JidoTest.Case
      import JidoTest.Helpers.Assertions

      @moduletag :capture_log
    end
  end

  setup _tags do
    # Setup any test state or fixtures needed
    :ok
  end

  @doc """
  Stop the given process with a non-normal exit reason.
  Can accept either a PID or registered name.
  """
  def shutdown_test_process(pid, reason \\ :shutdown)

  def shutdown_test_process(pid, reason) when is_pid(pid) do
    Process.unlink(pid)
    Process.exit(pid, reason)

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, _, _, _}, 5_000
  end

  def shutdown_test_process(name, reason) when is_atom(name) do
    case Process.whereis(name) do
      nil -> :ok
      pid -> shutdown_test_process(pid, reason)
    end
  end
end
