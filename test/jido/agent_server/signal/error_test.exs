defmodule Jido.AgentServer.Signal.ErrorTest do
  use ExUnit.Case, async: true

  alias Jido.AgentServer.Signal.Error, as: ErrorSignal

  @data %{
    agent_id: "agent-1",
    turn_id: "turn-1",
    status: :failed,
    stage: :execute,
    committed?: false,
    error: %{type: :execution, message: "Action failed", details: %{}, retryable?: true}
  }

  test "creates error Signals for each terminal failure status" do
    for status <- [:failed, :cancelled, :timed_out, :indeterminate] do
      data = %{@data | status: status}

      assert {:ok,
              %Jido.Signal{
                type: "jido.agent.error",
                source: "/agent/agent-1",
                data: ^data
              }} = ErrorSignal.new(data, source: "/agent/agent-1")
    end
  end

  test "rejects incomplete error reports and invalid outcome fields" do
    for data <- [
          Map.delete(@data, :turn_id),
          %{@data | status: :succeeded},
          %{@data | stage: :unknown},
          %{@data | committed?: "false"},
          %{@data | error: :raw_error}
        ] do
      assert {:error, _issues} = ErrorSignal.new(data)
    end
  end
end
