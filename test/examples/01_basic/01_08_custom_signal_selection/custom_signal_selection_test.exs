defmodule JidoTest.Examples.Basic.CustomSignalSelectionTest do
  use JidoTest.BasicSDKCase

  alias Jido.Examples.CustomSignalSelection, as: Example

  test "custom selection converts input and preserves the source Signal", %{jido: jido} do
    signal = Example.raw_signal!("3")
    agent = Example.new!(id: unique_id("custom-selection-direct"))

    assert {:ok, turn} = Example.handle_signal(signal, agent)
    assert turn.input == %{amount: 3}
    assert turn.source_signal === signal

    server = start_agent!(jido, Example)
    assert {:ok, direct, []} = Jido.Agent.cmd(agent, signal)
    assert {:ok, live} = Jido.AgentServer.call(server, signal)
    assert direct.state.count == 3
    assert live.state.count == direct.state.count
  end

  test "normal Signals delegate to declared routes", %{jido: jido} do
    signal =
      Jido.Signal.new!(
        "examples.basic.custom_signal.normal",
        %{amount: 2},
        source: "/examples/basic/custom_signal_selection"
      )

    agent = Example.new!(id: unique_id("custom-selection-normal"))
    server = start_agent!(jido, Example)

    assert {:ok, direct, []} = Jido.Agent.cmd(agent, signal)
    assert {:ok, live} = Jido.AgentServer.call(server, signal)
    assert direct.state.count == 2
    assert live.state == direct.state
  end

  test "explicit rejection does not fall back or commit", %{jido: jido} do
    server = start_agent!(jido, Example, error_policy: observe_errors())
    before = Jido.AgentServer.snapshot(server)

    signal =
      Jido.Signal.new!(
        "examples.basic.custom_signal.reject",
        %{amount: 10},
        source: "/examples/basic/custom_signal_selection"
      )

    assert {:error, %Jido.Error.ValidationError{}} =
             Jido.Agent.cmd(before.agent, signal)

    assert {:error, %Jido.Error.ValidationError{}} = Jido.AgentServer.call(server, signal)
    assert Jido.AgentServer.snapshot(server) == before
  end
end
