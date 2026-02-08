defmodule JidoTest.AgentServer.Lifecycle.NoopTest do
  use ExUnit.Case, async: true

  alias Jido.AgentServer.Lifecycle.Noop

  test "init/2 returns state unchanged" do
    state = %{status: :idle}
    assert Noop.init([], state) == state
  end

  test "handle_event/2 continues with unchanged state" do
    state = %{status: :running}
    assert {:cont, ^state} = Noop.handle_event(:any_event, state)
  end

  test "terminate/2 is a no-op" do
    assert :ok = Noop.terminate(:shutdown, %{status: :stopping})
  end
end
