defmodule JidoActionTest.ProcessCleanup do
  @moduledoc false

  import ExUnit.Assertions

  def assert_supervisor_quiescent(supervisor, timeout \\ 5_000) do
    await_empty(supervisor, System.monotonic_time(:millisecond) + timeout)
  end

  defp await_empty(supervisor, deadline) do
    case Task.Supervisor.children(supervisor) do
      [] ->
        :ok

      children ->
        if System.monotonic_time(:millisecond) >= deadline do
          state =
            Enum.map(children, &{&1, Process.info(&1, [:status, :current_function, :messages])})

          flunk("supervisor did not become quiescent; remaining children: #{inspect(state)}")
        end

        # Each call yields to the supervisor. A worker DOWN does not order the
        # supervisor's own exit notification. Do not sleep or stop live work.
        await_empty(supervisor, deadline)
    end
  end
end
