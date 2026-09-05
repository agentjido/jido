defmodule JidoTest.Examples.Workflow.ConditionalRoutesTest do
  use JidoTest.WorkflowSDKCase
  alias Jido.Examples.ConditionalRoutes, as: Example
  alias JidoTest.WorkflowService, as: Service

  test "only the first matching option runs and the fallback remains lazy", %{jido: jido} do
    client = start_supervised!({Service, %{primary: {:ok, %{answer: "primary"}}}})
    server = start_agent!(jido, Example)

    assert {:ok, agent} =
             Server.call(server, Example.fetch_signal!(),
               context: context([], %{service: {Service, client}})
             )

    assert agent.state.route == :primary
    assert_receive {:step, :primary, _, _}
    refute_received {:step, :second, _, _}
    refute_received {:step, :fallback, _, _}
    assert Service.calls(client) == [{:primary, %{}}]
    assert Server.snapshot(server).state_version == 1
  end

  test "explicit expected errors select fallback and permanent errors select rejection", %{
    jido: jido
  } do
    server = start_agent!(jido, Example)

    client =
      start_supervised!(
        {Service, %{primary: {:error, :unavailable}, fallback: {:ok, %{answer: "cache"}}}}
      )

    assert {:ok, agent} =
             Server.call(server, Example.fetch_signal!(), context: %{service: {Service, client}})

    assert agent.state == %{route: :fallback, result: %{answer: "cache"}}
    assert Service.calls(client) == [{:primary, %{}}, {:fallback, %{}}]
    before = Server.snapshot(server)
    denied = start_supervised!({Service, %{primary: {:error, :forbidden}}}, id: :denied)

    assert {:error, error} =
             Server.call(server, Example.fetch_signal!(),
               context: context([], %{service: {Service, denied}})
             )

    assert Enum.any?(errors(error), &(&1.message == "primary rejected"))
    assert_receive {:step, :reject, _, _}
    assert Service.calls(denied) == [{:primary, %{}}]
    assert Server.snapshot(server) == before
  end

  test "a selected Action failure does not enter another option or otherwise", %{jido: jido} do
    client = start_supervised!({Service, %{primary: {:ok, %{answer: "primary"}}}})
    server = start_agent!(jido, Example)

    assert {:ok, _} =
             Server.call(server, Example.fetch_signal!(), context: %{service: {Service, client}})

    before = Server.snapshot(server)

    assert {:error, error} =
             Server.call(server, Example.fetch_signal!(),
               context: context([], %{service: {Service, client}, reject_selected: true})
             )

    assert Enum.any?(errors(error), &(&1.message == "selected route failed"))
    assert_receive {:step, :primary, _, _}
    refute_received {:step, :second, _, _}
    refute_received {:step, :reject, _, _}
    refute_received {:step, :fallback, _, _}
    assert Server.snapshot(server) == before
  end
end
