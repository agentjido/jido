defmodule Jido.Agent.FlowEffectsTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server
  alias Jido.Signal

  defmodule Submit do
    use Jido.Agent.Directive
    defstruct [:key]

    @impl true
    def validate(%__MODULE__{key: key} = request) when is_binary(key), do: {:ok, request}
    def validate(_), do: {:error, Jido.Error.validation_error("invalid booking key")}
  end

  defmodule AgentFacet do
    use Jido.Agent.Plugin
    @impl true
    def directives(_), do: [Submit]
  end

  defmodule ServerFacet do
    use Jido.AgentServer.Plugin
    @impl true
    def dispatch(_, request, context, _) do
      server = Jido.whereis_agent(context.jido, context.agent_id, partition: context.partition)
      # Read the public snapshot inside dispatch. The commit must already exist.
      snapshot = Server.snapshot(server)
      send(context.turn_context.observer, {:submitted, request.key, snapshot})
      :ok
    end
  end

  defmodule Plugin do
    use Jido.Plugin, agent: AgentFacet, agent_server: ServerFacet
  end

  defmodule Approve do
    use Jido.Action, name: "effect_approve_booking"
    @impl true
    def run(params, context) do
      state = %{context.agent_state | status: Map.get(params, :status, :submitting)}
      request = %Submit{key: Map.get(params, :key, "booking-1")}
      requests = if params[:invalid_batch], do: [request, %Submit{key: 42}], else: [request]
      effects = if params[:invalid_effects], do: %{}, else: requests
      {:ok, state, effects}
    end
  end

  defmodule StreamResult do
    use Jido.Action, name: "stream_is_not_agent_state"
    @impl true
    def run(_, _), do: {:ok, Jido.Action.Output.stream(1..2), [%Submit{key: "stream"}]}
  end

  defmodule Fail do
    use Jido.Action, name: "failed_booking_flow"
    @impl true
    def run(_, _), do: {:error, :booking_rejected, [%Submit{key: "failed"}]}
  end

  defmodule Flow do
    use Jido.Flow, name: "approve_booking_flow"

    flow do
      step "approve", action: Approve, params: input()
      output result("approve")
    end
  end

  defmodule FailedFlow do
    use Jido.Flow, name: "failed_approve_booking_flow"

    flow do
      step "approve", action: Approve, params: input()
      step "fail", action: Fail, params: %{}, needs: ["approve"]
      output result("fail")
    end
  end

  defmodule MultipleFlow do
    use Jido.Flow, name: "multiple_approve_booking_flow"

    flow do
      step "z_first", action: Approve, params: %{key: "first"}
      step "a_second", action: Approve, params: %{key: "second"}, needs: ["z_first"]
      output result("a_second")
    end
  end

  defmodule BookingAgent do
    use Jido.Agent, name: "flow_effect_booking_agent"

    agent do
      schema Zoi.object(%{
               status:
                 Zoi.enum([:awaiting_approval, :submitting]) |> Zoi.default(:awaiting_approval)
             })

      plugin Plugin
    end

    routes do
      route "approve.direct", Approve
      route "approve.flow", Flow
      route "approve.failed", FailedFlow
      route "approve.error", Fail
      route "approve.multiple", MultipleFlow
      route "approve.stream", StreamResult
    end
  end

  test "direct and Flow commands return the same candidate and directives without dispatch" do
    agent = BookingAgent.new!()
    context = %{observer: self()}

    assert {:ok, candidate, [%Submit{key: "booking-1"}]} =
             expected = Jido.Agent.cmd(agent, command_signal("direct"), context: context)

    assert candidate.state.status == :submitting
    assert Jido.Agent.cmd(agent, command_signal("flow"), context: context) == expected
    refute_received {:submitted, _, _}
  end

  test "a Flow booking request runs only after the live state commit", %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, BookingAgent)

    assert {:ok, candidate} =
             Server.call(server, command_signal("flow"), context: %{observer: self()})

    assert_receive {:submitted, "booking-1", snapshot}, 1_000
    assert snapshot == %{agent: candidate, state_version: 1}
    assert candidate.state.status == :submitting
  end

  test "state validation, directive validation, and Flow failure prevent commit and dispatch", %{
    jido: jido
  } do
    {:ok, server} = Jido.start_agent(jido, BookingAgent)
    initial = Server.snapshot(server)

    for command <- [
          command_signal("flow", %{status: :invalid}),
          command_signal("flow", %{key: 42}),
          command_signal("flow", %{invalid_batch: true}),
          command_signal("flow", %{invalid_effects: true}),
          command_signal("stream"),
          command_signal("error"),
          command_signal("failed")
        ] do
      assert {:error, _} = Jido.Agent.cmd(initial.agent, command, context: %{observer: self()})
      assert {:error, _} = Server.call(server, command, context: %{observer: self()})
      assert Server.snapshot(server) == initial
      # The call reply and snapshot are barriers after the failed Turn.
      refute_received {:submitted, _, _}
    end
  end

  test "all Flow requests reach the caller in order and dispatch once after one commit", %{
    jido: jido
  } do
    agent = BookingAgent.new!()

    assert {:ok, candidate, [%Submit{key: "first"}, %Submit{key: "second"}]} =
             Jido.Agent.cmd(agent, command_signal("multiple"), context: %{observer: self()})

    refute_received {:submitted, _, _}
    {:ok, server} = Jido.start_agent(jido, agent)

    assert {:ok, ^candidate} =
             Server.call(server, command_signal("multiple"), context: %{observer: self()})

    assert_receive {:submitted, "first", first_snapshot}
    assert_receive {:submitted, "second", second_snapshot}
    assert first_snapshot == %{agent: candidate, state_version: 1}
    assert second_snapshot == first_snapshot
    assert Server.snapshot(server) == first_snapshot
    refute_received {:submitted, _, _}
  end

  defp command_signal(route, data \\ %{}),
    do: Signal.new!("approve." <> route, data, source: "/test")
end
