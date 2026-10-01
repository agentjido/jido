defmodule JidoTest.AgentServer.ObservabilityRedactionTest do
  use JidoTest.Case, async: true
  import ExUnit.CaptureLog

  defmodule Failure do
    use Jido.Action, name: "observable_redaction_failure"

    def run(_, _) do
      {:error,
       Jido.Error.execution_error("Failed",
         details: %{nested: [{:password, "secret-redaction-9387"}, :other]}
       )}
    end
  end

  test "cast failure logs and emitted errors sanitize structured secret fields", %{jido: jido} do
    definition =
      Jido.Agent.new!(name: "observable_redaction", routes: [{"probe.failure", Failure}])

    {:ok, server} =
      Jido.start_agent(jido, Jido.Agent.instantiate!(definition),
        error_policy: {:emit_signal, {:pid, target: self()}}
      )

    source = signal("probe.failure")

    log =
      capture_log([metadata: [:reason]], fn ->
        :ok = Jido.AgentServer.cast(server, source)
        assert_receive {:signal, %Jido.Signal{type: "jido.agent.error"} = report}, 5_000
        refute Jason.encode!(report.data.error) =~ "secret-redaction-9387"
        assert report.data.error.type == :execution_error
        assert report.data.error.details.nested == ["{:password, \"[REDACTED]\"}", :other]
        assert Jido.Signal.get_context(report, "jidocausationid") == source.id
        Jido.AgentServer.snapshot(server)
      end)

    assert log =~ "Agent Signal cast failed"
    assert log =~ "[REDACTED]"
    refute log =~ "secret-redaction-9387"
  end
end
