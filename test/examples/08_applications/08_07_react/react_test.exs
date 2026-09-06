defmodule JidoTest.Examples.Applications.ReactTest do
  use JidoTest.Case, async: false

  @moduletag :example

  alias Jido.AgentServer, as: Server
  alias Jido.Signal
  alias Jido.Examples.Applications.React.Agent

  test "message history survives later Turns and commits before scheduled work", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, Agent, id: unique_id("react"))

    signal =
      Signal.new!(
        "react.reason",
        %{
          messages: [%{role: :user, content: "Research this"}],
          script: [{:tool, :search}, {:answer, "Complete"}],
          test: self()
        },
        source: "/test/react"
      )

    assert {:ok, committed} = Server.call(pid, signal, 5_000)

    assert_receive {:react_stage, {:llm, {:tool, :search}}}
    assert_receive {:react_stage, {:tool, :search}}
    assert_receive {:react_stage, {:llm, {:answer, "Complete"}}}
    assert_receive {:react_stage, :commit}

    assert committed.state.answers == ["Complete"]

    assert committed.state.messages == [
             %{role: :user, content: "Research this"},
             %{role: :tool, name: :search, content: "tool result"},
             %{role: :assistant, content: "Complete", messages_seen: 2}
           ]

    assert_receive {:react_messages, [%{role: :user, content: "Research this"}]}

    assert_receive {:react_messages,
                    [%{role: :user, content: "Research this"}, %{role: :tool, name: :search}]}

    eventually(fn -> Server.agent(pid).state.followups == 1 end)
    eventually(fn -> Server.status(pid).phase == :idle end)
    assert Server.status(pid).state_version == 2
    before = Server.snapshot(pid)
    observer = self()

    before_model = fn messages ->
      send(observer, {:model_waiting, self(), messages})

      receive do
        :release_model -> :ok
      after
        1_000 -> raise "model barrier was not released"
      end
    end

    next_message = %{role: :user, content: "What did you find?"}

    next_signal =
      Signal.new!(
        "react.reason",
        %{messages: [next_message], script: [{:answer, "A result"}], test: self()},
        source: "/test/react"
      )

    caller =
      Task.async(fn -> Server.call(pid, next_signal, context: %{before_model: before_model}) end)

    assert_receive {:model_waiting, worker, model_messages}, 1_000
    assert model_messages == committed.state.messages ++ [next_message]
    assert Server.snapshot(pid) == before
    send(worker, :release_model)
    assert {:ok, next} = Task.await(caller)
    assert next.state.answers == ["Complete", "A result"]

    assert next.state.messages ==
             model_messages ++ [%{role: :assistant, content: "A result", messages_seen: 4}]

    eventually(fn -> Server.agent(pid).state.followups == 2 end)
    eventually(fn -> Server.status(pid).phase == :idle end)
    assert Server.status(pid).state_version == 4
    assert Server.agent(pid).state.messages == next.state.messages
  end

  test "a failed tool loop preserves the previously committed history", %{jido: jido} do
    {:ok, pid} =
      Jido.start_agent(jido, Agent,
        id: unique_id("react-failure"),
        error_policy: fn _, _ -> :continue end
      )

    seed =
      Signal.new!(
        "react.reason",
        %{
          messages: [%{role: :user, content: "Hello"}],
          script: [{:answer, "Ready"}],
          test: self()
        },
        source: "/test/react"
      )

    assert {:ok, _} = Server.call(pid, seed)
    eventually(fn -> Server.agent(pid).state.followups == 1 end)
    eventually(fn -> Server.status(pid).phase == :idle end)
    before = Server.snapshot(pid)

    failure =
      Signal.new!(
        "react.reason",
        %{
          messages: [%{role: :user, content: "Research this"}],
          script: [{:tool, :search}, {:error, :offline}],
          test: self()
        },
        source: "/test/react"
      )

    assert {:error, %Jido.Action.Error.ExecutionFailureError{}} = Server.call(pid, failure)
    assert_receive {:react_stage, {:tool, :search}}
    assert Server.snapshot(pid) == before
  end
end
