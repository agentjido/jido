Code.require_file("nested_organization.ex", __DIR__)

defmodule Jido.Examples.Collaboration.NestedOrganizationTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.Examples.Collaboration.NestedOrganization.{Company, Worker}

  test "nested departments isolate worker failure and stop as one owned subtree" do
    suffix = System.unique_integer([:positive])
    jido = :"nested_organization_#{suffix}"
    start_supervised!({Jido, name: jido}, id: jido)

    assert {:ok, root} = Jido.start_agent(jido, Company, id: "company")
    assert :ok = AgentServer.await_ready(root)
    assert Jido.resident_agent_count(jido) == 15

    workers =
      jido
      |> Jido.list_agents()
      |> Enum.flat_map(fn {_id, pid} ->
        if AgentServer.snapshot(pid).agent.module == Worker, do: [pid], else: []
      end)
      |> Enum.sort()

    assert length(workers) == 8
    [failed, successful | _rest] = workers

    assert {:ok, %AgentServer.TurnResult{status: :failed}} =
             AgentServer.call(failed, Worker.work_signal!(%{fail: true}))

    assert {:ok, %AgentServer.TurnResult{status: :committed}} =
             AgentServer.call(successful, Worker.work_signal!(%{fail: false}))

    assert AgentServer.snapshot(failed).agent_revision == 0
    assert AgentServer.snapshot(successful).agent.state.completed == 1
    refute Map.has_key?(Map.from_struct(AgentServer.snapshot(root)), :children)

    assert :ok = Jido.stop_agent(jido, root)
    assert :ok = wait_until(fn -> Jido.resident_agent_count(jido) == 0 end)
  end

  defp wait_until(fun) do
    deadline = System.monotonic_time(:millisecond) + 1_000
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
