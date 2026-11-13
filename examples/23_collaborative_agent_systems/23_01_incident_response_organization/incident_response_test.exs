Code.require_file("incident_response.ex", __DIR__)

defmodule Jido.Examples.Collaboration.IncidentResponseTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.Examples.Collaboration.IncidentResponse.{AuditTeam, Coordinator}

  test "one failed team is isolated while the durable coordinator resolves the incident" do
    jido = start_persistent_jido()

    assert {:ok, root} =
             Jido.start_agent(jido, Coordinator,
               id: "incident-coordinator",
               persistence: :inherit
             )

    assert :ok = AgentServer.await_ready(root)
    assert Jido.resident_agent_count(jido) == 6

    report =
      Coordinator.report_signal!(%{
        incident_id: "incident-42",
        severity: "high",
        fail_audit: true
      })

    assert {:ok, %AgentServer.TurnResult{status: :committed}} =
             AgentServer.call(root, report)

    assert :ok = wait_until(fn -> AgentServer.snapshot(root).agent.state.status == :awaiting_approval end)

    audit = find_agent(jido, AuditTeam)
    assert Process.alive?(audit)
    assert AgentServer.snapshot(audit).agent_revision == 0

    assert {:ok, %AgentServer.TurnResult{status: :committed}} =
             AgentServer.call(root, Coordinator.approve_signal!(%{incident_id: "incident-42"}))

    resolved = AgentServer.snapshot(root)
    assert resolved.agent.state.status == :resolved
    assert resolved.agent.state.remediation == "shed noncritical load"
    assert Enum.map(resolved.agent.state.events, & &1.event) == [:reported, :contained, :approved]
    refute Map.has_key?(Map.from_struct(resolved), :children)

    address = resolved.agent_address
    activation_id = resolved.agent_activation_id
    assert :ok = Jido.stop_agent(jido, root)
    assert :ok = wait_until(fn -> Jido.resident_agent_count(jido) == 0 end)

    assert {:ok, replacement} = Jido.activate_agent(jido, address)
    assert :ok = AgentServer.await_ready(replacement)
    restored = AgentServer.snapshot(replacement)
    assert restored.agent.state.status == :resolved
    refute restored.agent_activation_id == activation_id
    assert restored.agent_address == address

    assert :ok = Jido.stop_agent(jido, replacement)
  end

  defp find_agent(jido, module) do
    jido
    |> Jido.list_agents()
    |> Enum.find_value(fn {_id, pid} ->
      if AgentServer.snapshot(pid).agent.module == module, do: pid
    end)
  end

  defp start_persistent_jido do
    suffix = System.unique_integer([:positive])
    name = :"incident_response_#{suffix}"
    persistence = {Jido.Persistence.ETS, table: Module.concat(__MODULE__, "Store#{suffix}")}

    start_supervised!(
      {Jido, name: name, namespace: "examples/incident-response/#{suffix}", persistence: persistence},
      id: name
    )

    name
  end

  defp wait_until(fun, timeout \\ 1_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_until(fun, deadline)
  end

  defp do_wait_until(fun, deadline) do
    cond do
      fun.() ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, :timeout}

      true ->
        receive do
        after
          5 -> do_wait_until(fun, deadline)
        end
    end
  end
end
