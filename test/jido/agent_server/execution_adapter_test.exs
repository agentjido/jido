defmodule Jido.AgentServer.ExecutionAdapterTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer.ExecutionAdapter

  test "stale callback completion preserves the current timer" do
    adapter = %ExecutionAdapter{ref: make_ref(), timeout: 60_000}
    first_token = make_ref()
    first = ExecutionAdapter.callback_started(adapter, first_token, :handle_message)
    current_token = make_ref()
    current = ExecutionAdapter.callback_started(first, current_token, :handle_message)

    assert Process.read_timer(first.timer) == false
    assert ExecutionAdapter.callback_finished(current, first_token) == current
    assert is_integer(Process.read_timer(current.timer))
    refute ExecutionAdapter.timeout?(current, first.timer, first_token)
    assert ExecutionAdapter.timeout?(current, current.timer, current_token)

    finished = ExecutionAdapter.callback_finished(current, current_token)
    assert finished == %{current | callback_token: nil, timer: nil}
    assert Process.read_timer(current.timer) == false
    assert ExecutionAdapter.callback_finished(finished, current_token) == finished
  end
end
