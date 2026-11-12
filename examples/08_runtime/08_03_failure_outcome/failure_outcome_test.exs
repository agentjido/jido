Code.require_file("failure_outcome.ex", __DIR__)

defmodule Jido.Examples.Runtime.FailureOutcomeTest do
  use Jido.Test.Case, async: true
  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.Examples.FailureOutcome

  test "accepted failures are data and do not change committed state", %{jido: jido} do
    {:ok, server} =
      Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, FailureOutcome, id: unique_id("failure-outcome"))

    before = AgentServer.snapshot(server)
    {:ok, reject} = FailureOutcome.reject_signal(%{reason: "invalid"})

    assert {:ok,
            %Jido.AgentServer.TurnResult{
              status: :failed,
              durability: :memory,
              error: %Jido.Error.ExecutionError{}
            }} = AgentServer.call(server, reject)

    assert AgentServer.snapshot(server) == before

    {:ok, accept} = FailureOutcome.accept_signal(%{name: "saved"})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             AgentServer.call(server, accept)

    assert AgentServer.snapshot(server).agent.state.accepted == ["saved"]
    assert AgentServer.status(server).work_state == :idle
  end
end
