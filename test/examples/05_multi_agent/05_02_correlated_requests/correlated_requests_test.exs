defmodule JidoTest.Examples.MultiAgent.CorrelatedRequestsTest do
  use JidoTest.FeatureSDKCase
  @moduletag group: :multi_agent
  alias Jido.Examples.{CorrelatedRequests, Worker}

  defp start_request(jido) do
    parent = start_agent!(jido, CorrelatedRequests, error_policy: :log_only)

    assert {:ok, pending} =
             CorrelatedRequests.request(parent, "request", 7,
               context: %{worker: observed(Worker, :on_work)}
             )

    assert pending.state.status == :waiting
    assert_receive {:feature_work, work, %{request_id: "request", value: 7}}, 1_000
    eventually(fn -> Server.snapshot(parent).state_version == 2 end)
    {parent, work}
  end

  test "the child completes its own Turn before the parent accepts the result", %{jido: jido} do
    {parent, work} = start_request(jido)
    child = Server.children(parent)["request"]
    assert state(parent).result == nil
    assert Server.snapshot(child.pid).state_version == 0
    send(work, :release)
    eventually(fn -> state(parent).status == :completed end)
    assert state(parent).result == 14
    eventually(fn -> Server.children(parent) == %{} end)
  end

  test "wrong correlation and duplicate requests cannot settle pending work", %{jido: jido} do
    {parent, work} = start_request(jido)
    before = Server.snapshot(parent)

    for overrides <- [%{request_id: "old"}, %{tag: "wrong"}, %{job_id: "wrong"}] do
      data =
        Map.merge(
          %{request_id: "request", job_id: "request", tag: "request", value: 90},
          overrides
        )

      assert {:error, _} = Server.call(parent, signal("examples.work.result", data))
      assert Server.snapshot(parent) == before
    end

    assert {:error, _} = CorrelatedRequests.request(parent, "request", 8)
    send(work, :release)
    eventually(fn -> state(parent).status == :completed end)
    assert {:error, _} = CorrelatedRequests.request(parent, "request", 8)
    assert state(parent).result == 14
  end

  test "cancellation stops the child and its active execution worker", %{jido: jido} do
    {parent, work} = start_request(jido)
    ref = Process.monitor(work)
    assert {:ok, cancelled} = CorrelatedRequests.cancel(parent, "request")
    assert cancelled.state.status == :cancelled
    assert_receive {:DOWN, ^ref, :process, ^work, _}, 1_000
    eventually(fn -> Server.children(parent) == %{} end)
    assert state(parent).result == nil
  end

  test "child process loss ends the request and a fresh request can succeed", %{jido: jido} do
    {parent, work} = start_request(jido)
    ref = Process.monitor(work)
    Process.exit(Server.children(parent)["request"].pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^work, _}, 1_000
    eventually(fn -> state(parent).status == :failed end)
    assert {:ok, _} = CorrelatedRequests.request(parent, "next", 4)
    eventually(fn -> state(parent).status == :completed end)
    assert state(parent).result == 8
  end

  test "a child Action error becomes a failed request through the stop-on-error policy", %{
    jido: jido
  } do
    {parent, work} = start_request(jido)
    send(work, :fail)
    eventually(fn -> state(parent).status == :failed end)
    eventually(fn -> Server.children(parent) == %{} end)
    assert state(parent).result == nil
  end

  test "the child execution deadline ends blocked work and settles the parent", %{jido: jido} do
    {parent, work} = start_request(jido)
    ref = Process.monitor(work)
    assert_receive {:DOWN, ^ref, :process, ^work, _}, 2_000
    eventually(fn -> state(parent).status == :failed end)
    eventually(fn -> Server.children(parent) == %{} end)
  end
end
