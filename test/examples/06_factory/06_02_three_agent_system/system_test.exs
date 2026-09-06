defmodule JidoTest.Examples.Factory.SystemTest do
  use JidoTest.Case, async: true
  @moduletag :example

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Factory.{Conversation, Tools}
  alias JidoTest.FactoryHTTP, as: HTTP

  test "LLM tool commands and factory events cross three Agents while the model is busy", %{
    jido: jido
  } do
    system = HTTP.system!(jido, :workshop)
    test_pid = self()

    context =
      HTTP.context(fn body ->
        if length(body["messages"]) == 1 do
          HTTP.tool("submit_work", %{"goal" => "Make a demo"})
        else
          send(test_pid, {:tool_result, self(), body})

          receive do
            :release -> HTTP.text("The factory accepted the job.")
          end
        end
      end)

    assert {:ok, agent} =
             Conversation.ask(system.conversation, "chat-1", "Start work", context: context)

    assert agent.state.status == :thinking
    assert_receive {:tool_result, worker, body}, 5_000
    assert Jason.encode!(body) =~ "chat-1"

    assert_eventually(HTTP.state(system.factory).jobs["chat-1"].status == :running,
      timeout: 2_000
    )

    assert_eventually(
      Enum.any?(HTTP.state(system.conversation).events, &(&1.status == "running"))
    )

    assert HTTP.state(system.conversation).status == :thinking
    assert Enum.any?(HTTP.state(system.owner).events, &(&1.status == "queued"))
    send(worker, :release)
    assert_eventually(HTTP.state(system.conversation).answer == "The factory accepted the job.")
    assert {:ok, _} = Tools.command(jido, system.factory_id, :cancel, "cancel", "chat-1", "")
    assert_eventually(List.last(HTTP.state(system.conversation).events).status == "cancelled")
  end

  test "pause, resume, duplicate submit, and stale ticks have explicit state rules", %{jido: jido} do
    system = HTTP.system!(jido, :workshop)
    assert {:ok, job} = Tools.command(jido, system.factory_id, :submit, "job", "", "Goal")
    assert {:ok, duplicate} = Tools.command(jido, system.factory_id, :submit, "job", "", "Goal")
    assert duplicate.id == job.id
    assert duplicate.goal == job.goal
    assert map_size(HTTP.state(system.factory).jobs) == 1
    assert {:error, _} = Tools.command(jido, system.factory_id, :submit, "job", "", "Changed")
    assert {:ok, _} = Tools.command(jido, system.factory_id, :pause, "pause", "job", "")
    tick = signal("factory.worker.progress", %{job_id: "job", generation: 0, step: 0})
    before = Server.snapshot(system.factory)
    assert {:error, _} = Server.call(system.factory, tick)
    assert Server.snapshot(system.factory) == before
    assert {:ok, _} = Tools.command(jido, system.factory_id, :resume, "resume", "job", "")
    assert {:ok, _} = Server.call(system.factory, signal("factory.workshop.poll", %{}))

    for step <- 0..2 do
      tick = signal("factory.worker.progress", %{job_id: "job", generation: 2, step: step})
      assert {:ok, _} = Server.call(system.factory, tick)
    end

    assert HTTP.state(system.factory).jobs["job"].status == :completed
    assert_eventually(List.last(HTTP.state(system.conversation).events).status == "completed")
  end

  test "invalid tool arguments cannot change factory state", %{jido: jido} do
    system = HTTP.system!(jido, :workshop)
    tools = Tools.definitions(jido, system.factory_id, "job", %{})
    submit = Enum.find(tools, &(&1.name == "submit_work"))
    assert {:error, _} = ReqLLM.Tool.execute(submit, %{"goal" => 42})
    assert HTTP.state(system.factory).jobs == %{}
  end

  test "owner shutdown stops children and a pending model task", %{jido: jido} do
    system = HTTP.system!(jido, :workshop)
    test_pid = self()

    context =
      HTTP.context(fn _ ->
        send(test_pid, {:waiting, self()})

        receive do
          :release -> HTTP.text("done")
        end
      end)

    assert {:ok, _} = Conversation.ask(system.conversation, "chat", "Hello", context: context)
    assert_receive {:waiting, worker}, 5_000
    refs = for pid <- [system.conversation, system.factory, worker], do: Process.monitor(pid)
    assert :ok = Jido.stop_agent(jido, system.owner)
    for ref <- refs, do: assert_receive({:DOWN, ^ref, :process, _, _}, 2_000)
  end

  test "timer work completes without another user command", %{jido: jido} do
    system = HTTP.system!(jido, :workshop, step_delay_ms: 5)
    command = signal("factory.command", %{operation: :submit, request_id: "job", goal: "demo"})
    assert {:ok, _} = Server.call(system.factory, command)
    assert_eventually(HTTP.state(system.factory).jobs["job"].status == :completed, timeout: 3_000)
  end

  test "IEx starts a ready system and returns from the prompt without stopping it", %{jido: jido} do
    alias Jido.Examples.Factory.IEx, as: Chat
    assert {:ok, session} = Chat.start(:workshop, jido: jido)
    assert {:ok, %{jobs: %{}}} = Chat.status(session)

    output =
      ExUnit.CaptureIO.capture_io([input: "/back\n"], fn ->
        assert :ok = Chat.chat(session)
      end)

    assert output =~ "you>"
    assert Process.alive?(session.owner)
    assert :ok = Chat.stop(session)
    refute Process.alive?(session.owner)
    assert :ok = Chat.stop(session)
  end

  test "IEx basic chat prints a real ReqLLM response through the HTTP fixture", %{jido: jido} do
    alias Jido.Examples.Factory.IEx, as: Chat
    context = HTTP.context(fn _ -> HTTP.text("Hello from the fixture") end)
    assert {:ok, session} = Chat.start(:conversation, jido: jido, context: context)
    output = ExUnit.CaptureIO.capture_io(fn -> assert :ok = Chat.say(session, "Hello") end)
    assert output =~ "assistant> Hello from the fixture"
    assert :ok = Chat.stop(session)
  end

  test "IEx command prompt runs factory controls and keeps EOF sessions alive", %{jido: jido} do
    alias Jido.Examples.Factory.IEx, as: Chat
    assert {:ok, session} = Chat.start(:workshop, jido: jido)
    assert {:ok, _} = Tools.command(jido, session.factory_id, :submit, "job", "", "Demo")

    output =
      ExUnit.CaptureIO.capture_io(
        [input: "\n/status\n/job job\n/events\n/pause job\n/resume job\n/cancel job\n"],
        fn -> assert :ok = Chat.chat(session) end
      )

    assert output =~ "factory:"
    assert output =~ "job:"
    assert output =~ "events:"
    assert Process.alive?(session.owner)
    assert {:ok, job} = Chat.job(session, "job")
    assert job.job.status == :cancelled
    assert is_list(Chat.events(session))
    assert :ok = Chat.stop(session)
  end

  test "IEx conversation mode reports unavailable factory controls and closed sessions", %{
    jido: jido
  } do
    alias Jido.Examples.Factory.IEx, as: Chat
    assert {:ok, session} = Chat.start(:conversation, jido: jido)
    assert {:error, :no_factory} = Chat.status(session)
    assert {:error, :no_factory} = Chat.job(session, "job")
    assert {:error, :no_factory} = Chat.control(session, :cancel, "job")
    assert Chat.events(session) == []
    assert :ok = Chat.stop(session)
    assert {:error, :conversation_unavailable} = Chat.say(session, "Hello")
    assert Chat.events(%{session | mode: :workshop}) == []
    assert :ok = Chat.stop(%{session | observer: nil})
  end

  test "IEx system chat uses the local model fixture and observes the answer", %{jido: jido} do
    alias Jido.Examples.Factory.IEx, as: Chat
    context = HTTP.context(fn _ -> HTTP.text("System reply") end)
    assert {:ok, session} = Chat.start(:workshop, jido: jido, context: context)
    assert :ok = Chat.say(session, "Hello")
    conversation = Jido.whereis_agent(jido, session.conversation_id)
    eventually(fn -> Server.agent(conversation).state.answer == "System reply" end)
    assert :ok = Chat.stop(session)
  end

  test "IEx department startup returns only when all heads are available", %{jido: jido} do
    alias Jido.Examples.Factory.IEx, as: Chat
    assert {:ok, session} = Chat.start(:departments, jido: jido)

    for name <- ["research", "design", "build", "quality"] do
      assert is_pid(Jido.whereis_agent(jido, "#{session.factory_id}/#{name}"))
    end

    assert :ok = Chat.stop(session)
  end

  test "chat prints an authentication error and accepts the next message", %{jido: jido} do
    alias Jido.Examples.Factory.IEx, as: Chat

    context =
      HTTP.context(fn body ->
        if hd(body["messages"])["content"] == "Fail" do
          {401,
           %{"error" => %{"type" => "authentication_error", "message" => "API key is invalid."}}}
        else
          HTTP.text("Ready")
        end
      end)

    assert {:ok, session} = Chat.start(:conversation, jido: jido, context: context)

    output =
      ExUnit.CaptureIO.capture_io([input: "Fail\nHello\n/quit\n"], fn ->
        assert :ok = Chat.chat(session)
      end)

    assert output =~ "Model: anthropic:claude-haiku-4-5"
    assert output =~ "request failed: Model"
    assert output =~ "HTTP 401"
    assert output =~ "API key is invalid"
    assert output =~ "assistant> Ready"
    refute output =~ "fixture-key"
  end

  test "asynchronous model failures retain safe provider details", %{jido: jido} do
    system = HTTP.system!(jido, :workshop)

    context =
      HTTP.context(fn _ ->
        {401,
         %{
           "error" => %{
             "type" => "authentication_error",
             "message" => "API key is invalid: fixture-key"
           }
         }}
      end)

    assert {:ok, _} = Conversation.ask(system.conversation, "chat", "Hello", context: context)
    assert_eventually(HTTP.state(system.conversation).status == :idle)
    error = HTTP.state(system.conversation).error
    assert error =~ "HTTP 401"
    assert error =~ "API key is invalid: [REDACTED]"
    refute error =~ "fixture-key"
  end
end
