Code.require_file("transcript.ex", __DIR__)
Code.require_file("recall_turn.ex", __DIR__)
Code.require_file("long_running.ex", __DIR__)
Code.require_file("support/offline_client.ex", __DIR__)

defmodule Jido.Examples.ContextMemory.LongRunningTest do
  use ExUnit.Case, async: true

  @moduletag :integration
  @moduletag :tmp_dir

  alias Jido.{AgentServer, Session, Thread}
  alias Jido.AI.Thread.Projection
  alias Jido.Examples.ContextMemory.LongRunning
  alias Jido.Examples.ContextMemory.LongRunning.{Agent, OfflineClient, RecallTurn, Transcript}

  defmodule EmptySummary do
    def generate_text(model, context, _options),
      do: {:ok, %ReqLLM.Response{id: "empty-summary", model: model, context: context}}
  end

  test "both compaction modes leave the complete archive available to ReAct", %{tmp_dir: path} do
    with_app(path, fn app, database ->
      for number <- 1..6 do
        assert {:ok, %{number: ^number, status: :completed}} = LongRunning.ask(app, "Observation #{number}")
      end

      assert :ok = LongRunning.compact(app)
      assert %{through: 0, text: nil} = Transcript.summary(app.table)
      assert {:ok, original} = Transcript.read(app.table, 1)
      assert [:ai_message, :ai_model_attempt, :ai_message, :ai_request_outcome] = kinds(original)

      assert {:ok, window} = LongRunning.window(app)
      assert {:ok, messages} = Projection.messages(window)
      assert user_messages(messages) == ["Observation 3", "Observation 4", "Observation 5", "Observation 6"]

      failing = %{app | compaction: {:model, "offline:archive-summary", EmptySummary}}
      assert {:error, :invalid_compaction_summary} = LongRunning.compact(failing)
      assert %{through: 0, text: nil} = Transcript.summary(app.table)

      model = %{app | compaction: {:model, "offline:archive-summary", OfflineClient}}
      assert :ok = LongRunning.compact(model)
      assert %{through: 2, text: "Reviewed archived history through Turn 2."} = Transcript.summary(app.table)
      assert :ok = LongRunning.compact(model)

      assert :ok = Transcript.close(app.table)
      assert {:ok, _table} = Transcript.open(app.table, database)
      assert {:ok, ^original} = Transcript.read(app.table, 1)
      assert {:ok, deterministic} = LongRunning.window(app)
      assert {:ok, deterministic_messages} = Projection.messages(deterministic)
      assert deterministic_messages == messages

      assert {:ok, with_summary} = LongRunning.window(model)
      assert {:ok, messages} = Projection.messages(with_summary)
      assert [summary, "Observation 3" | _rest] = user_messages(messages)
      assert summary =~ "Archive summary through Turn 2"
      refute "Observation 1" in user_messages(messages)

      assert {:ok, recalled} = LongRunning.ask(model, "Recall turn 1")
      assert :ai_tool_attempt in kinds(recalled)
      assert archived_tool_output(recalled)["turn"] == 1
      assert archived_tool_output(recalled)["excerpt"] =~ "Observation 1"

      assert {:ok, missing} = LongRunning.ask(model, "Recall turn 900")
      assert archived_tool_output(missing) == %{"turn" => 900, "status" => "not_found"}
      assert {:ok, server} = Jido.resolve_agent(app.instance, app.address)
      assert %{agent_revision: 8, agent: %{state: %{session: nil}}} = AgentServer.snapshot(server)
    end)
  end

  test "recovers a reply after caller loss, before or after the archive write", %{tmp_dir: path} do
    with_app(path, fn app, _database ->
      assert {:ok, original_server} = Jido.resolve_agent(app.instance, app.address)

      for number <- 1..2 do
        task =
          Task.async(fn ->
            assert {:ok, pending} = LongRunning.submit(app, "Keep this committed result")
            assert {:ok, %{status: :committed}} = AgentServer.await(pending, 15_000)
            pending.turn_id
          end)

        turn_id = Task.await(task, 20_000)
        assert {:error, {:pending_turn, ^turn_id}} = LongRunning.submit(app, "Wait for recovery")
        assert {:ok, %{reply: %{data: reply}}} = Jido.turn_result(app.instance, app.address, turn_id)
        record = %{number: number, turn_id: turn_id, status: reply.status, entries: reply.session_entries}
        assert {:error, :not_found} = Transcript.read(app.table, number)

        if number == 2 do
          assert :ok = Transcript.append(app.table, record)
          assert {:error, :conflicting_turn} = Transcript.append(app.table, %{record | entries: []})
        end

        assert {:ok, ^record} = LongRunning.recover(app)
        assert {:error, :not_found} = Transcript.pending(app.table)
        assert Transcript.count(app.table) == number
        assert {:error, :not_found} = Jido.turn_result(app.instance, app.address, turn_id)
      end

      assert {:ok, restored} = Jido.resolve_agent(app.instance, app.address)
      refute restored == original_server
      assert %{agent_revision: 2, agent: %{state: %{session: nil}}} = AgentServer.snapshot(restored)
      assert {:ok, %{number: 3}} = LongRunning.ask(app, "Continue on the same address")

      assert :ok = Transcript.reserve(app.table, %{number: 4, turn_id: "unknown"})
      assert {:error, {:unresolved_turn, "unknown"}} = LongRunning.recover(app)
      assert {:error, {:pending_turn, "unknown"}} = LongRunning.submit(app, "Do not retry blindly")
    end)
  end

  test "the byte limit drops a whole Turn and recall can page its full message", %{tmp_dir: path} do
    with_app(path, fn app, _database ->
      content = String.duplicate("é", 7_000)

      session = Session.new()
      {:ok, session} = Projection.append(session, %{role: :user, content: content})
      entries = Enum.map(session.thread.entries, &Thread.Entry.encode/1)
      assert :ok = Transcript.append(app.table, %{number: 1, turn_id: "large", status: :completed, entries: entries})

      assert {:ok, window} = LongRunning.window(app)
      assert {:ok, []} = Projection.messages(window)

      context = %{transcript_table: app.table}
      assert {:ok, %{excerpt: first, next_offset: next}} = Jido.Exec.run(RecallTurn, %{number: 1}, context)
      assert is_integer(next)
      assert byte_size(first) <= 512 and String.valid?(first)
      assert {:ok, %{excerpt: second}} = Jido.Exec.run(RecallTurn, %{number: 1, offset: next}, context)
      assert byte_size(second) <= 512 and String.valid?(second)

      assert first <> second ==
               String.byte_slice(JSON.encode!(hd(session.thread.entries).payload), 0, byte_size(first <> second))
    end)
  end

  defp with_app(path, run) do
    instance = __MODULE__
    namespace = "example/long-running/test"
    database = Path.join(path, "test.dets")
    {:ok, table} = Transcript.open(__MODULE__, database)

    try do
      start_supervised!({Jido, name: instance, namespace: namespace, persistence: {Jido.Persistence.File, path: path}})
      address = Jido.Agent.Address.new!(namespace: namespace, id: "conversation")
      assert {:ok, ^address} = Jido.create_agent(instance, address, Agent)
      assert {:ok, _server} = Jido.activate_agent(instance, address)

      run.(
        %{instance: instance, address: address, table: table, inference: OfflineClient, compaction: :deterministic},
        database
      )
    after
      :ok = Transcript.close(table)
    end
  end

  defp kinds(record) do
    for entry <- record.entries do
      {:ok, decoded} = Thread.Entry.decode(entry)
      decoded.kind
    end
  end

  defp user_messages(messages), do: for(message <- messages, message.role == :user, do: message.content)

  defp archived_tool_output(record) do
    Enum.find_value(record.entries, fn entry ->
      {:ok, decoded} = Thread.Entry.decode(entry)
      if decoded.kind == :ai_message and decoded.payload["role"] == "tool", do: decoded.payload["output"]
    end)
  end
end
