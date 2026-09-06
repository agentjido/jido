defmodule JidoTest.Examples.Factory.BatchTest do
  use JidoTest.Case, async: true
  @moduletag :example

  alias Jido.Examples.Factory.{Conversation, Tools, Workshop}
  alias JidoTest.FactoryHTTP, as: HTTP

  defp batch(id, goals), do: signal("factory.submit_jobs", %{request_id: id, goals: goals})

  test "a batch creates distinct jobs in order and a retry does not add jobs or events" do
    original = Workshop.new!()
    goals = Enum.map(1..20, &"Goal #{&1}")
    request = batch("batch", goals)
    assert {:ok, agent, effects} = Workshop.cmd(original, request)
    ids = Enum.map(1..20, &"batch/#{&1}")
    assert original.state.jobs == %{}
    assert agent.state.queue == ids
    assert Enum.map(ids, &agent.state.jobs[&1].goal) == goals
    assert agent.state.active_job_id == ""
    assert length(effects) == 20
    assert Enum.all?(effects, &match?(%Jido.Agent.Directive.EmitToParent{}, &1))
    assert {:ok, same, []} = Workshop.cmd(agent, request)
    assert same.state == agent.state
    assert {:error, _} = Workshop.cmd(agent, batch("batch", ["Changed"]))
  end

  test "capacity and job ID conflicts reject the whole batch" do
    goals = Enum.map(1..19, &"Goal #{&1}")
    assert {:ok, agent, _} = Workshop.cmd(Workshop.new!(), batch("first", goals))
    assert {:error, _} = Workshop.cmd(agent, batch("second", ["One", "Two"]))
    assert map_size(agent.state.jobs) == 19
    assert {:ok, full, [_]} = Workshop.cmd(agent, batch("second", ["One"]))
    assert map_size(full.state.jobs) == 20

    assert {:ok, occupied, _} =
             Workshop.cmd(
               Workshop.new!(),
               signal("factory.command", %{
                 operation: :submit,
                 request_id: "batch/1",
                 goal: "Existing"
               })
             )

    assert {:error, _} = Workshop.cmd(occupied, batch("batch", ["One", "Two"]))
    assert map_size(occupied.state.jobs) == 1
  end

  test "one invalid goal rejects all batch jobs before effects" do
    agent = Workshop.new!()

    for goals <- [[], ["Valid", ""], ["Valid", "   "], ["Valid", 42]] do
      assert {:error, _} = Workshop.cmd(agent, batch("invalid", goals))
    end

    assert agent.state.jobs == %{}
    assert agent.state.events == []
  end

  test "tool input is validated before a factory Signal is sent", %{jido: jido} do
    system = HTTP.system!(jido, :workshop)
    tools = Tools.definitions(jido, system.factory_id, "invalid", %{}) |> Map.new(&{&1.name, &1})

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        for input <- [%{}, %{"goal" => ""}, %{"goal" => "   "}, %{"goal" => 42}] do
          assert {:error, _} = ReqLLM.Tool.execute(tools["submit_work"], input)
        end

        for input <- [
              %{},
              %{"count" => 0},
              %{"count" => 21},
              %{"count" => "3"},
              %{"count" => 3, "goals" => ["Only one"]},
              %{"count" => 2, "goals" => ["Valid", "   "]}
            ] do
          assert {:error, _} = ReqLLM.Tool.execute(tools["submit_jobs"], input)
        end
      end)

    refute log =~ "signal.error"
    assert HTTP.state(system.factory).jobs == %{}
    assert HTTP.state(system.factory).events == []
  end

  test "a count-only tool call uses numbered demo goals and retries return the same IDs", %{
    jido: jido
  } do
    system = HTTP.system!(jido, :workshop)

    tool =
      Enum.find(
        Tools.definitions(jido, system.factory_id, "three", %{}),
        &(&1.name == "submit_jobs")
      )

    assert {:ok, receipt} = ReqLLM.Tool.execute(tool, %{"count" => 3})
    assert receipt.job_ids == ["three/1", "three/2", "three/3"]
    assert Enum.map(receipt.jobs, & &1.goal) == Enum.map(1..3, &"Demonstration job #{&1}")
    assert {:ok, retry} = ReqLLM.Tool.execute(tool, %{"count" => 3, "goals" => []})
    assert retry.job_ids == receipt.job_ids
    assert map_size(HTTP.state(system.factory).jobs) == 3
    assert Enum.count(HTTP.state(system.factory).events, &(&1.status == "queued")) == 3
    assert_eventually(length(HTTP.state(system.conversation).events) >= 3)
  end

  test "the model receives a clear input error and can correct a rejected call", %{jido: jido} do
    system = HTTP.system!(jido, :workshop)
    test_pid = self()

    context =
      HTTP.context(fn body ->
        case length(body["messages"]) do
          1 ->
            HTTP.tool("submit_work", %{"goal" => ""})

          3 ->
            send(test_pid, {:input_error, Jason.encode!(body)})
            HTTP.tool("submit_jobs", %{"count" => 3, "goals" => []})

          _ ->
            send(test_pid, {:receipt, Jason.encode!(body)})
            HTTP.text("Queued three demonstration jobs.")
        end
      end)

    assert {:ok, _} =
             Conversation.ask(system.conversation, "corrected", "add 3 jobs to the factory",
               context: context
             )

    assert_receive {:input_error, error}, 5_000
    assert error =~ "Invalid submit_work arguments"
    assert_receive {:receipt, receipt}, 5_000
    for index <- 1..3, do: assert(receipt =~ "corrected/#{index}")

    assert_eventually(
      HTTP.state(system.conversation).answer == "Queued three demonstration jobs."
    )

    assert map_size(HTTP.state(system.factory).jobs) == 3
  end

  test "explicit goals are preserved and departments reject batch submission", %{jido: jido} do
    workshop = HTTP.system!(jido, :workshop)
    tools = Tools.definitions(jido, workshop.factory_id, "specific", %{})
    tool = Enum.find(tools, &(&1.name == "submit_jobs"))

    assert {:ok, receipt} =
             ReqLLM.Tool.execute(tool, %{"count" => 2, "goals" => ["Report", "Review"]})

    assert Enum.map(receipt.jobs, & &1.goal) == ["Report", "Review"]
    departments = HTTP.system!(jido, :departments)
    assert {:error, _} = Tools.submit_jobs(jido, departments.factory_id, "batch", ["Report"])
    assert HTTP.state(departments.factory).jobs == %{}
  end
end
