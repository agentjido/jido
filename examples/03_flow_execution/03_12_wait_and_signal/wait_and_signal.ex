defmodule Jido.Examples.Execution.WaitAndSignal do
  use Jido.Flow, name: "example_exec_wait_and_signal"

  flow do
    selection "decision" do
      await "approved", event: "example.approved", match: %{request_id: input(:request_id)}
      await "denied", event: "example.denied", match: %{request_id: input(:request_id)}
      timer "expired", after_ms: 60_000
    end

    output result("decision")
  end
end
