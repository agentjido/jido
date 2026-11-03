defmodule JidoTest.Telemetry.AgentServerTest do
  use Covenant.Case, component: "jido.telemetry", async: false

  alias Jido.Telemetry.AgentServer

  @moduletag obligation: ["jido.telemetry.I1", "jido.telemetry.I2", "jido.telemetry.I3"]

  test "the AgentServer event owner defines the complete metric catalog" do
    assert AgentServer.span_metrics() == [
             {[:jido, :agent_server, :turn], [:stop], [:status, :stage]}
           ]

    assert AgentServer.point_metrics() == [
             {[:jido, :agent_server, :lifecycle, :start], []},
             {[:jido, :agent_server, :lifecycle, :stop], []},
             {[:jido, :agent_server, :commit], [:status]},
             {[:jido, :agent_server, :directives, :returned], []},
             {[:jido, :agent_server, :effects, :start], []},
             {[:jido, :agent_server, :effects, :stop], [:status, :stage]},
             {[:jido, :agent_server, :turn, :settled], [:status, :stage]}
           ]

    assert Enum.sort(AgentServer.event_names()) ==
             Enum.sort([
               [:jido, :agent_server, :turn, :start],
               [:jido, :agent_server, :turn, :stop],
               [:jido, :agent_server, :lifecycle, :start],
               [:jido, :agent_server, :lifecycle, :stop],
               [:jido, :agent_server, :commit],
               [:jido, :agent_server, :directives, :returned],
               [:jido, :agent_server, :effects, :start],
               [:jido, :agent_server, :effects, :stop],
               [:jido, :agent_server, :turn, :settled]
             ])
  end

  test "the owner emits one committed Turn and its later effects" do
    handler = {__MODULE__, make_ref()}
    events = AgentServer.event_names()

    :ok =
      :telemetry.attach_many(
        handler,
        events,
        fn event, measurements, metadata, owner ->
          send(owner, {:event, event, measurements, metadata})
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert :ok = AgentServer.lifecycle(:start, "agent-1")
    span = AgentServer.start_turn(%{agent_id: "agent-1", turn_id: "turn-1", private: :drop})
    assert :ok = AgentServer.start_effects(span.metadata, 2)

    assert :ok =
             AgentServer.settle_turn(
               span,
               %{status: :succeeded, stage: :commit, committed?: true},
               %{state_version_before: 1, state_version_after: 2, directive_count: 2},
               true,
               2
             )

    assert :ok = AgentServer.finish_effects(span.metadata, :failed, :directive, 1, 2)

    assert_receive {:event, [:jido, :agent_server, :lifecycle, :start], _, lifecycle}
    assert lifecycle.agent_id == "agent-1"
    refute Map.has_key?(lifecycle, :private)

    assert_receive {:event, [:jido, :agent_server, :turn, :start], _, turn_start}
    assert turn_start.agent_id == "agent-1"
    refute Map.has_key?(turn_start, :private)

    assert_receive {:event, [:jido, :agent_server, :effects, :start], %{directive_count: 2}, _}
    assert_receive {:event, [:jido, :agent_server, :commit], %{state_version_after: 2}, %{status: :ok}}
    assert_receive {:event, [:jido, :agent_server, :directives, :returned], %{directive_count: 2}, _}
    assert_receive {:event, [:jido, :agent_server, :turn, :stop], _, %{status: :ok}}
    assert_receive {:event, [:jido, :agent_server, :turn, :settled], _, %{status: :ok}}

    assert_receive {:event, [:jido, :agent_server, :effects, :stop], %{directive_completed: 1, directive_count: 2},
                    %{status: :error, stage: :directive}}
  end
end
