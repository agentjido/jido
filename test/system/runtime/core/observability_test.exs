Code.require_file("support/counter.exs", __DIR__)

defmodule JidoTest.System.Runtime.ObservabilityTest do
  use Jido.Test.Case, async: false

  @moduletag :system

  alias Jido.AgentServer, as: Server
  alias JidoTest.System.Runtime.Counter

  test "Turn telemetry reports commit boundaries without the private payload", c do
    owner = self()
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:jido, :agent_server, :turn, :stop],
        fn event, measurements, metadata, target ->
          send(target, {:turn_stop, event, measurements, metadata})
        end,
        owner
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    {:ok, server} = Jido.Test.AgentServer.Assertions.start_agent(c.jido, Counter)
    secret = "PRIVATE_RUNTIME_#{unique_id()}"

    assert {:ok, saved, []} =
             Server.call(server, signal("system.runtime.add", %{delta: 4, secret: secret}))

    assert_receive {:turn_stop, [:jido, :agent_server, :turn, :stop], measurements, metadata}, 5_000
    assert metadata.committed? == true
    assert metadata.stage == :commit
    assert measurements.duration > 0
    refute inspect({measurements, metadata}) =~ secret

    assert {:error, %Jido.Error.ValidationError{}} =
             Server.call(server, signal("system.runtime.add", %{delta: "bad", secret: secret}))

    assert_receive {:turn_stop, [:jido, :agent_server, :turn, :stop], _measurements, rejected}, 5_000
    assert rejected.committed? == false
    assert rejected.stage == :evaluate
    refute inspect(rejected) =~ secret
    assert Server.agent(server) == saved
    assert :ok = Jido.stop_agent(c.jido, server)
  end
end
