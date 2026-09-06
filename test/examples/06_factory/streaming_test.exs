defmodule JidoTest.Examples.Factory.StreamingTest do
  use JidoTest.Case, async: true
  @moduletag :example

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Factory.{Conversation, LiveConversation, Model, Tools}
  alias Jido.Examples.Factory.IEx, as: Chat
  alias JidoTest.{FactoryHTTP, FactorySSE}

  test "text reaches the caller before stream completion; only a full answer commits", %{
    jido: jido
  } do
    test_pid = self()

    fixture =
      start_supervised!(
        {FactorySSE,
         fn socket, body ->
           assert body["stream"]
           FactorySSE.start_text(socket)
           FactorySSE.text(socket, "Hello")
           send(test_pid, {:first_chunk, self()})

           receive do
             :finish ->
               FactorySSE.text(socket, " world")
               FactorySSE.finish(socket)
           end
         end}
      )

    context =
      Map.put(FactorySSE.context(fixture), :on_stream, fn id, event ->
        send(test_pid, {id, event})
      end)

    {:ok, agent} = Jido.start_agent(jido, LiveConversation, exec_opts: [timeout: 15_000])
    before = Server.agent(agent)

    task =
      Task.async(fn ->
        LiveConversation.chat(agent, "stream", "Hello", context: context, timeout: 20_000)
      end)

    assert_receive {:first_chunk, fixture_task}, 5_000
    assert_receive {"stream", {:delta, "Hello"}}, 5_000
    assert Server.agent(agent) == before
    send(fixture_task, :finish)
    assert {:ok, result} = Task.await(task, 10_000)
    assert result.state.answer == "Hello world"
    assert Enum.count(result.state.messages, &(&1.role == :assistant)) == 1
  end

  test "split tool arguments execute once after completion; factory feedback arrives during streaming",
       %{jido: jido} do
    system = FactoryHTTP.system!(jido, :workshop)
    test_pid = self()

    fixture =
      start_supervised!(
        {FactorySSE,
         fn socket, body ->
           if length(body["messages"]) == 1 do
             FactorySSE.start_tool(socket, "submit_work")
             FactorySSE.arguments(socket, "{\"goal\":")
             send(test_pid, {:partial_tool, self()})

             receive do
               :finish_tool ->
                 FactorySSE.arguments(socket, "\"Streamed goal\"}")
                 FactorySSE.finish(socket, "tool_use")
             end
           else
             send(test_pid, {:tool_result, self(), body})
             FactorySSE.start_text(socket)
             FactorySSE.text(socket, "Accepted")

             receive do
               :finish -> FactorySSE.finish(socket)
             end
           end
         end}
      )

    context = FactorySSE.context(fixture)

    assert {:ok, _} =
             Conversation.ask(system.conversation, "stream-job", "Start work", context: context)

    assert_receive {:partial_tool, fixture_task}, 5_000
    assert FactoryHTTP.state(system.factory).jobs == %{}
    send(fixture_task, :finish_tool)
    assert_receive {:tool_result, fixture_task, body}, 5_000
    assert Jason.encode!(body) =~ "stream-job"
    assert map_size(FactoryHTTP.state(system.factory).jobs) == 1
    assert FactoryHTTP.state(system.factory).jobs["stream-job"].goal == "Streamed goal"

    assert_eventually(
      Enum.any?(FactoryHTTP.state(system.conversation).events, &(&1.status == "running")),
      timeout: 2_000
    )

    assert FactoryHTTP.state(system.conversation).status == :thinking
    send(fixture_task, :finish)
    assert_eventually(FactoryHTTP.state(system.conversation).answer == "Accepted", timeout: 2_000)
    assert {:ok, _} = Tools.command(jido, system.factory_id, :cancel, "cancel", "stream-job", "")
  end

  test "the terminal prints each chunk once and does not repeat the final answer", %{jido: jido} do
    test_pid = self()

    fixture =
      start_supervised!(
        {FactorySSE,
         fn socket, _body ->
           FactorySSE.start_text(socket)
           FactorySSE.text(socket, "Hello")
           send(test_pid, {:printing, self()})

           receive do
             :finish ->
               FactorySSE.text(socket, " there")
               FactorySSE.finish(socket)
           end
         end}
      )

    {:ok, session} = Chat.start(:conversation, jido: jido, context: FactorySSE.context(fixture))
    {:ok, device} = StringIO.open("")

    task =
      Task.async(fn ->
        Process.group_leader(self(), device)
        Chat.say(session, "Hello")
      end)

    assert_receive {:printing, fixture_task}, 5_000
    assert_eventually(elem(StringIO.contents(device), 1) == "assistant> Hello", timeout: 2_000)
    send(fixture_task, :finish)
    assert :ok = Task.await(task, 10_000)
    assert elem(StringIO.contents(device), 1) == "assistant> Hello there\n"
    Chat.stop(session)
    StringIO.close(device)
  end

  test "a streamed batch creates three jobs only after complete tool arguments", %{jido: jido} do
    system = FactoryHTTP.system!(jido, :workshop)
    test_pid = self()

    fixture =
      start_supervised!(
        {FactorySSE,
         fn socket, body ->
           if length(body["messages"]) == 1 do
             FactorySSE.start_tool(socket, "submit_jobs")
             FactorySSE.arguments(socket, "{\"count\":3,")
             send(test_pid, {:partial_batch, self()})

             receive do
               :finish_batch ->
                 FactorySSE.arguments(socket, "\"goals\":[]}")
                 FactorySSE.finish(socket, "tool_use")
             end
           else
             send(test_pid, {:batch_receipt, Jason.encode!(body)})
             FactorySSE.start_text(socket)
             FactorySSE.text(socket, "Queued three demo jobs.")
             FactorySSE.finish(socket)
           end
         end}
      )

    assert {:ok, _} =
             Conversation.ask(system.conversation, "three", "add 3 jobs to the factory",
               context: FactorySSE.context(fixture)
             )

    assert_receive {:partial_batch, fixture_task}, 5_000
    assert FactoryHTTP.state(system.factory).jobs == %{}
    send(fixture_task, :finish_batch)
    assert_receive {:batch_receipt, receipt}, 5_000
    for index <- 1..3, do: assert(receipt =~ "three/#{index}")
    assert map_size(FactoryHTTP.state(system.factory).jobs) == 3
    assert_eventually(FactoryHTTP.state(system.conversation).answer == "Queued three demo jobs.")
  end

  test "streaming authentication errors retain safe status details" do
    fixture =
      start_supervised!(
        {FactorySSE, fn socket, _body -> FactorySSE.error(socket, 401, "API key is invalid.") end}
      )

    assert {:error, error} = Model.reply("Hello", FactorySSE.context(fixture))
    assert error.details.status == 401
    assert error.message =~ "API key is invalid"
    refute inspect(error) =~ "fixture-key"
  end

  test "a stream without a completion event cannot commit a partial answer", %{jido: jido} do
    fixture =
      start_supervised!(
        {FactorySSE,
         fn socket, _body ->
           FactorySSE.start_text(socket)
           FactorySSE.text(socket, "Partial")
           FactorySSE.disconnect(socket)
         end}
      )

    {:ok, agent} = Jido.start_agent(jido, LiveConversation)
    before = Server.agent(agent)

    assert {:error, _} =
             LiveConversation.chat(agent, "partial", "Hello",
               context: FactorySSE.context(fixture)
             )

    assert Server.agent(agent) == before
  end

  test "owner shutdown closes a pending streaming HTTP connection", %{jido: jido} do
    system = FactoryHTTP.system!(jido, :workshop)
    test_pid = self()

    fixture =
      start_supervised!(
        {FactorySSE,
         fn socket, _body ->
           FactorySSE.start_text(socket)
           FactorySSE.text(socket, "Waiting")
           send(test_pid, :connected)
           send(test_pid, {:connection_ended, :gen_tcp.recv(socket, 0, 5_000)})
         end}
      )

    assert {:ok, _} =
             Conversation.ask(system.conversation, "close", "Hello",
               context: FactorySSE.context(fixture)
             )

    assert_receive :connected, 5_000
    assert :ok = Jido.stop_agent(jido, system.owner)
    assert_receive {:connection_ended, {:error, :closed}}, 5_000
  end

  test "the terminal marks a partial stream as failed and preserves history", %{jido: jido} do
    fixture =
      start_supervised!(
        {FactorySSE,
         fn socket, _ ->
           FactorySSE.start_text(socket)
           FactorySSE.text(socket, "Unfinished text")
           FactorySSE.disconnect(socket)
         end}
      )

    {:ok, session} = Chat.start(:conversation, jido: jido, context: FactorySSE.context(fixture))
    before = Server.agent(session.owner)

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert {:error, error} = Chat.say(session, "Hello")
        assert error.message =~ "before a complete response"
      end)

    assert output =~ "assistant> Unfinished text\n"
    assert output =~ "[partial response; request failed]"
    assert Server.agent(session.owner) == before
    Chat.stop(session)
  end

  test "the workshop terminal mixes stream chunks and factory events without repeating the answer",
       %{jido: jido} do
    test_pid = self()

    fixture =
      start_supervised!(
        {FactorySSE,
         fn socket, _ ->
           FactorySSE.start_text(socket)
           FactorySSE.text(socket, "Streamed prefix")
           send(test_pid, {:streaming, self()})

           receive do
             :finish ->
               FactorySSE.text(socket, " and suffix")
               FactorySSE.finish(socket)
           end
         end}
      )

    {:ok, session} = Chat.start(:workshop, jido: jido, context: FactorySSE.context(fixture))
    {:ok, device} = StringIO.open("")

    task =
      Task.async(fn ->
        Process.group_leader(self(), device)
        Chat.say(session, "Hello")
      end)

    assert :ok = Task.await(task)
    assert_receive {:streaming, fixture_task}, 5_000
    assert_eventually(elem(StringIO.contents(device), 1) =~ "assistant> Streamed prefix")

    assert {:ok, _} =
             Tools.command(jido, session.factory_id, :submit, "event-job", "", "Demo", %{})

    assert_eventually(elem(StringIO.contents(device), 1) =~ "[factory event-job queued]")
    send(fixture_task, :finish)
    conversation = Jido.whereis_agent(jido, session.conversation_id)

    assert_eventually(FactoryHTTP.state(conversation).answer == "Streamed prefix and suffix",
      timeout: 2_000
    )

    assert {:ok, _} = Chat.control(session, :cancel, "event-job")

    try do
      assert_eventually(elem(StringIO.contents(device), 1) =~ "[factory event-job cancelled]")
    rescue
      error in ExUnit.AssertionError ->
        factory = Jido.whereis_agent(jido, session.factory_id)

        # Preserve process state when the assertion fails.
        # credo:disable-for-next-line Credo.Check.Warning.IoInspect
        IO.inspect(
          %{
            factory: Server.snapshot(factory),
            factory_status: Server.status(factory),
            owner: Server.snapshot(session.owner),
            conversation: Server.snapshot(conversation),
            observer: :sys.get_state(session.observer),
            output: elem(StringIO.contents(device), 1)
          },
          label: "Factory stream cancellation diagnostics",
          limit: :infinity
        )

        reraise error, __STACKTRACE__
    end

    output = elem(StringIO.contents(device), 1)
    assert length(Regex.scan(~r/Streamed prefix/, output)) == 1
    assert length(Regex.scan(~r/and suffix/, output)) == 1
    Chat.stop(session)
    StringIO.close(device)
  end
end
