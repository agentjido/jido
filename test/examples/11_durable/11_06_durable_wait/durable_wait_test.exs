defmodule JidoTest.Examples.Durable.DurableWaitTest do
  use JidoTest.Case, async: false
  @moduletag :example
  @moduletag :tmp_dir

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Durable.DurableWait, as: Example

  defp start(c) do
    id = unique_id("approval")
    persistence = {Jido.Persistence.File, path: c.tmp_dir}
    assert {:ok, server} = Jido.start_agent(c.jido, Example, id: id, persistence: persistence)
    assert :ok = Server.await_ready(server)
    {id, server, persistence}
  end

  test "the approval wait survives hibernation and accepts only one matching decision", c do
    {id, server, persistence} = start(c)
    deadline = System.system_time(:millisecond) + 3_600_000
    {:ok, request} = Example.request_signal(%{request_id: "report-1", deadline: deadline})
    assert {:ok, waiting, []} = Server.call(server, request)
    assert waiting.state.status == :waiting
    assert Server.status(server).active == nil
    assert :ok = Server.hibernate(server)
    assert {:ok, awake} = Jido.thaw(c.jido, Example, id, persistence: persistence)
    assert :ok = Server.await_ready(awake)
    assert Server.agent(awake) == waiting

    {:ok, wrong} = Example.resolve_signal(%{request_id: "other", decision: :approve})
    assert {:error, _} = Server.call(awake, wrong)
    assert Server.agent(awake) == waiting
    {:ok, approval} = Example.resolve_signal(%{request_id: "report-1", decision: :approve})
    assert {:ok, approved, []} = Server.call(awake, approval)
    assert approved.state.status == :approved
    assert approved.state.deadline == deadline
    assert {:error, _} = Server.call(awake, approval)
    assert Server.agent(awake) == approved
    assert :ok = Jido.stop_agent(c.jido, awake)
    assert Jido.agent_count(c.jido) == 0
  end

  for decision <- [:approve, :cancel] do
    test "an elapsed saved deadline expires on #{decision} without a new time budget", c do
      {id, server, persistence} = start(c)
      {:ok, request} = Example.request_signal(%{request_id: "late", deadline: 0})
      assert {:ok, _, []} = Server.call(server, request)
      assert :ok = Server.hibernate(server)
      assert {:ok, awake} = Jido.thaw(c.jido, Example, id, persistence: persistence)
      assert :ok = Server.await_ready(awake)
      {:ok, resolve} = Example.resolve_signal(%{request_id: "late", decision: unquote(decision)})
      assert {:ok, expired, []} = Server.call(awake, resolve)
      assert expired.state.status == :expired
      assert expired.state.deadline == 0
      assert :ok = Jido.stop_agent(c.jido, awake)
    end
  end

  test "cancellation closes a waiting request and survives restore", c do
    {id, server, persistence} = start(c)

    {:ok, request} =
      Example.request_signal(%{
        request_id: "cancel",
        deadline: System.system_time(:millisecond) + 3_600_000
      })

    assert {:ok, _, []} = Server.call(server, request)
    {:ok, cancel} = Example.resolve_signal(%{request_id: "cancel", decision: :cancel})
    assert {:ok, cancelled, []} = Server.call(server, cancel)
    assert cancelled.state.status == :cancelled
    assert :ok = Server.hibernate(server)
    assert {:ok, awake} = Jido.thaw(c.jido, Example, id, persistence: persistence)
    assert :ok = Server.await_ready(awake)
    assert Server.agent(awake) == cancelled
    {:ok, approval} = Example.resolve_signal(%{request_id: "cancel", decision: :approve})
    assert {:error, _} = Server.call(awake, approval)
    assert :ok = Jido.stop_agent(c.jido, awake)
  end
end
