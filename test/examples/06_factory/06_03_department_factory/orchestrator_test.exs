defmodule JidoTest.Examples.Factory.OrchestratorTest do
  use JidoTest.Case, async: true
  @moduletag :example
  @moduletag :integration
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Factory.{Plan, Tools}
  alias JidoTest.FactoryHTTP, as: HTTP

  defp controlled_context(test_pid) do
    HTTP.context(fn body ->
      system = Jason.encode!(body["system"])

      stage =
        Enum.find(Plan.steps(), &String.contains?(system, "You are the #{&1.id} department")).id

      send(test_pid, {:department, stage, self(), body})

      receive do
        :release ->
          HTTP.text("#{stage} artifact")

        :fail ->
          {401,
           %{
             "error" => %{
               "type" => "authentication_error",
               "message" => "API key is invalid: fixture-key"
             }
           }}
      end
    end)
  end

  test "four real heads follow the dependency plan and return artifacts to the conversation", %{
    jido: jido
  } do
    system = HTTP.system!(jido, :departments)
    context = controlled_context(self())

    assert {:ok, job} =
             Tools.command(
               jido,
               system.factory_id,
               :submit,
               "mission",
               "",
               "Build a report",
               context
             )

    assert job.status == :running
    assert_receive {:department, "research", research, _}, 5_000
    assert_receive {:department, "design", design, _}, 3_000
    assert map_size(HTTP.state(system.factory).active) == 2
    send(design, :release)

    assert_eventually(
      HTTP.state(system.factory).jobs["mission"].stages["design"].status == :completed
    )

    refute_receive {:department, "build", _, _}
    send(research, :release)
    assert_receive {:department, "build", build, body}, 3_000
    assert Jason.encode!(body) =~ "research artifact"
    assert Jason.encode!(body) =~ "design artifact"
    assert map_size(HTTP.state(system.factory).active) == 1
    send(build, :release)
    assert_receive {:department, "quality", quality, body}, 3_000
    assert Jason.encode!(body) =~ "build artifact"
    send(quality, :release)
    assert_eventually(HTTP.state(system.factory).jobs["mission"].status == :completed)
    assert_eventually(List.last(HTTP.state(system.conversation).events).status == "completed")
    assert HTTP.state(system.factory).jobs["mission"].stages["quality"].text == "quality artifact"
    assert HTTP.state(system.factory).active == %{}
    refute inspect(HTTP.state(system.factory)) =~ "fixture-key"

    assert {:ok, _} =
             Tools.command(
               jido,
               system.factory_id,
               :submit,
               "mission",
               "",
               "Build a report",
               context
             )

    refute_receive {:department, _, _, _}
  end

  test "pause allows current results but blocks downstream work; cancel rejects late results", %{
    jido: jido
  } do
    system = HTTP.system!(jido, :departments)
    context = controlled_context(self())

    assert {:ok, _} =
             Tools.command(jido, system.factory_id, :submit, "mission", "", "Goal", context)

    # Match the other initial department barriers during concurrent provider setup.
    assert_receive {:department, "research", research, _}, 5_000
    assert_receive {:department, "design", design, _}, 3_000
    assert {:ok, _} = Tools.command(jido, system.factory_id, :pause, "pause", "mission", "")
    send(research, :release)
    send(design, :release)
    assert_eventually(HTTP.state(system.factory).active == %{})
    assert HTTP.state(system.factory).jobs["mission"].status == :paused
    refute_receive {:department, "build", _, _}
    assert {:ok, _} = Tools.command(jido, system.factory_id, :resume, "resume", "mission", "")
    assert_receive {:department, "build", build, _}, 3_000
    assert {:ok, _} = Tools.command(jido, system.factory_id, :cancel, "cancel", "mission", "")
    send(build, :release)
    before = Server.snapshot(system.factory)

    late =
      signal("factory.async.result", %{
        request_id: "mission/build/1",
        status: :completed,
        error: "",
        result: %{
          attempt_id: "mission/build/1",
          job_id: "mission",
          department: "build",
          text: "late"
        }
      })

    assert {:error, _} = Server.call(system.factory, late)
    assert Server.snapshot(system.factory) == before
    refute_receive {:department, "quality", _, _}
    assert HTTP.state(system.factory).jobs["mission"].status == :cancelled
  end

  test "department failure fails the plan without starting dependent work", %{jido: jido} do
    system = HTTP.system!(jido, :departments)
    context = controlled_context(self())

    assert {:ok, _} =
             Tools.command(jido, system.factory_id, :submit, "mission", "", "Goal", context)

    assert_receive {:department, "research", research, _}, 5_000
    assert_receive {:department, "design", design, _}, 3_000
    send(research, :fail)

    assert_eventually(HTTP.state(system.factory).jobs["mission"].status == :failed,
      timeout: 2_000
    )

    send(design, :release)
    refute_receive {:department, "build", _, _}
    assert_eventually(List.last(HTTP.state(system.conversation).events).status == "failed")
    error = HTTP.state(system.factory).jobs["mission"].error
    assert error =~ "HTTP 401"
    assert error =~ "API key is invalid: [REDACTED]"
    refute error =~ "fixture-key"
  end

  test "the owner stops the complete seven-Agent tree", %{jido: jido} do
    system = HTTP.system!(jido, :departments)

    children =
      [system.conversation, system.factory] ++
        Enum.map(Plan.steps(), &Jido.whereis_agent(jido, "#{system.factory_id}/#{&1.id}"))

    refs = Enum.map(children, &Process.monitor/1)
    assert :ok = Jido.stop_agent(jido, system.owner)
    for ref <- refs, do: assert_receive({:DOWN, ^ref, :process, _, _}, 2_000)
  end
end
