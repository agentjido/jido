defmodule JidoTest.Examples.LLM.ReActAgentTest do
  use JidoTest.AgentCase

  @moduletag group: :llm
  @moduletag complexity: 3

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.ReActAgent
  alias Jido.Examples.ReActAgent.{BlockingModel, ScriptedModel, SearchTool}

  @prompt "How does the OTP agent model work?"
  @query "OTP agent model"
  @answer "OTP uses isolated processes and messages."

  test "one Signal runs the complete effectful ReAct Flow and commits once", %{jido: jido} do
    model =
      start_supervised!({ScriptedModel, [{:tool, "search", @query}, {:answer, @answer}]})

    search =
      start_supervised!({SearchTool, %{@query => "Agents own state and receive messages."}})

    agent = start_agent!(jido, ReActAgent)

    assert {:ok, committed} =
             ReActAgent.ask(agent, @prompt, {ScriptedModel, model}, %{
               "search" => {SearchTool, search}
             })

    assert committed.state.turns == 1
    assert committed.state.last_answer == @answer
    assert %{state_version: 1} = agent_result(agent)
    assert length(ScriptedModel.calls(model)) == 2
    assert SearchTool.queries(search) == [@query]
  end

  test "a failed Flow keeps Agent state but does not undo completed effects", %{jido: jido} do
    model =
      start_supervised!(
        {ScriptedModel, [{:tool, "search", @query}, {:error, :model_unavailable}]}
      )

    search =
      start_supervised!({SearchTool, %{@query => "Agents own state and receive messages."}})

    agent = start_quiet_agent(jido)

    assert {:error, _reason} =
             ReActAgent.ask(agent, @prompt, {ScriptedModel, model}, %{
               "search" => {SearchTool, search}
             })

    assert %{
             state: %{messages: [], last_answer: "", turns: 0},
             state_version: 0
           } = agent_result(agent)

    assert length(ScriptedModel.calls(model)) == 2
    assert SearchTool.queries(search) == [@query]
  end

  test "several tool calls remain inside one committed Turn", %{jido: jido} do
    second_query = "OTP supervision"

    model =
      start_supervised!(
        {ScriptedModel,
         [
           {:tool, "search", @query},
           {:tool, "search", second_query},
           {:answer, @answer}
         ]}
      )

    search =
      start_supervised!(
        {SearchTool,
         %{
           @query => "Agents own state.",
           second_query => "Supervisors restart failed children."
         }}
      )

    agent = start_agent!(jido, ReActAgent)

    assert {:ok, committed} =
             ReActAgent.ask(agent, @prompt, {ScriptedModel, model}, %{
               "search" => {SearchTool, search}
             })

    assert committed.state.last_answer == @answer
    assert agent_result(agent).state_version == 1
    assert length(ScriptedModel.calls(model)) == 3
    assert SearchTool.queries(search) == [@query, second_query]
  end

  test "an unknown tool fails without a commit", %{jido: jido} do
    model = start_supervised!({ScriptedModel, [{:tool, "missing", %{query: @query}}]})
    agent = start_quiet_agent(jido)

    assert {:error, _reason} =
             ReActAgent.ask(agent, @prompt, {ScriptedModel, model}, %{})

    assert %{state: %{turns: 0, messages: []}, state_version: 0} = agent_result(agent)
    assert length(ScriptedModel.calls(model)) == 1
  end

  test "a tool error preserves its completed model effect but does not commit", %{jido: jido} do
    model = start_supervised!({ScriptedModel, [{:tool, "search", @query}]})
    search = start_supervised!({SearchTool, %{@query => {:error, :search_unavailable}}})
    agent = start_quiet_agent(jido)

    assert {:error, _reason} =
             ReActAgent.ask(agent, @prompt, {ScriptedModel, model}, %{
               "search" => {SearchTool, search}
             })

    assert %{state: %{turns: 0, messages: []}, state_version: 0} = agent_result(agent)
    assert length(ScriptedModel.calls(model)) == 1
    assert SearchTool.queries(search) == [@query]
  end

  test "malformed model output fails before any tool effect", %{jido: jido} do
    model = start_supervised!({ScriptedModel, [{:tool, :search, @query}]})
    search = start_supervised!({SearchTool, %{@query => "unused"}})
    agent = start_quiet_agent(jido)

    assert {:error, _reason} =
             ReActAgent.ask(agent, @prompt, {ScriptedModel, model}, %{
               "search" => {SearchTool, search}
             })

    assert agent_result(agent).state_version == 0
    assert length(ScriptedModel.calls(model)) == 1
    assert SearchTool.queries(search) == []
  end

  test "the application step budget bounds recursive tool use", %{jido: jido} do
    model =
      start_supervised!(
        {ScriptedModel,
         [
           {:tool, "search", "one"},
           {:tool, "search", "two"},
           {:answer, "must not run"}
         ]}
      )

    search = start_supervised!({SearchTool, %{"one" => "1", "two" => "2"}})
    agent = start_quiet_agent(jido)

    assert {:error, _reason} =
             ReActAgent.ask(
               agent,
               @prompt,
               {ScriptedModel, model},
               %{"search" => {SearchTool, search}},
               max_steps: 2
             )

    assert agent_result(agent).state_version == 0
    assert length(ScriptedModel.calls(model)) == 2
    assert SearchTool.queries(search) == ["one", "two"]
  end

  test "a provider timeout fails without a commit", %{jido: jido} do
    model = start_supervised!({ScriptedModel, [{:error, :model_timeout}]})
    agent = start_quiet_agent(jido)

    assert {:error, _reason} =
             ReActAgent.ask(agent, @prompt, {ScriptedModel, model}, %{})

    assert agent_result(agent).state_version == 0
    assert length(ScriptedModel.calls(model)) == 1
  end

  test "cancelling the active Turn stops model work and keeps Agent state", %{jido: jido} do
    token = make_ref()
    owner = self()
    agent = start_quiet_agent(jido)

    request =
      Task.async(fn ->
        ReActAgent.ask(agent, @prompt, {BlockingModel, {owner, token}}, %{})
      end)

    assert_receive {:react_model_waiting, execution, ^token, _messages}, 1_000
    assert :ok = Server.cancel(agent)
    assert {:error, _reason} = Task.await(request, 1_000)
    eventually(fn -> not Process.alive?(execution) end)

    assert %{state: %{turns: 0, messages: []}, state_version: 0} = agent_result(agent)
    fresh = start_supervised!({ScriptedModel, [{:answer, "fresh context"}]})
    assert {:ok, agent} = ReActAgent.ask(agent, "next", {ScriptedModel, fresh}, %{})
    assert agent.state.last_answer == "fresh context"
    assert ScriptedModel.calls(fresh) == [[%{role: :user, content: "next"}]]
  end

  defmodule ObservedModel do
    def complete(client, messages),
      do: JidoTest.LLMService.call(client, :complete, %{messages: messages})
  end

  test "intermediate rounds expose prior state and the final transcript commits once", %{
    jido: jido
  } do
    import JidoTest.LLMSDKCase
    owner = self()

    model =
      service([
        {:ok, {:answer, "seed"}},
        {:ok, {:tool, "search", "one"}},
        blocked(owner, :round, {:ok, {:tool, "search", "two"}}),
        {:ok, {:answer, "done"}},
        {:ok, {:tool, "search", "one"}},
        {:error, :late_failure}
      ])

    search = start_supervised!({SearchTool, %{"one" => "1", "two" => "2"}})
    server = start_quiet_agent(jido)
    ctx = %{model: {ObservedModel, model}, tools: %{"search" => {SearchTool, search}}}
    assert {:ok, _} = Server.call(server, ReActAgent.ask_signal!("seed"), context: ctx)
    before = Server.snapshot(server)

    task =
      Task.async(fn -> Server.call(server, ReActAgent.ask_signal!("question"), context: ctx) end)

    assert_receive {:provider_waiting, :round, worker, :complete, %{messages: observed}}, 1_000

    expected =
      before.agent.state.messages ++
        [
          %{role: :user, content: "question"},
          %{role: :assistant, tool_call: %{name: "search", input: "one"}},
          %{role: :tool, name: "search", content: "1"}
        ]

    assert observed == expected
    assert Server.snapshot(server) == before
    send(worker, {:release, :round})
    assert {:ok, committed} = Task.await(task)

    assert committed.state.messages ==
             expected ++
               [
                 %{role: :assistant, tool_call: %{name: "search", input: "two"}},
                 %{role: :tool, name: "search", content: "2"},
                 %{role: :assistant, content: "done"}
               ]

    assert Server.snapshot(server).state_version == 2
    final = Server.snapshot(server)
    assert {:error, _} = Server.call(server, ReActAgent.ask_signal!("late"), context: ctx)
    assert Server.snapshot(server) == final
    assert SearchTool.queries(search) == ["one", "two", "one"]
    refute Map.has_key?(ReActAgent.ask_signal!("portable").data, :model)
  end

  test "the SDK continuation bound is separate from the model-step budget", %{jido: jido} do
    model = start_supervised!({ScriptedModel, [{:tool, "search", "one"}, {:answer, "unused"}]})
    search = start_supervised!({SearchTool, %{"one" => "1"}})

    server =
      start_agent!(jido, ReActAgent,
        error_policy: fn _, _ -> :continue end,
        exec_opts: [max_continuations: 1]
      )

    assert {:error, error} =
             ReActAgent.ask(
               server,
               "bounded",
               {ScriptedModel, model},
               %{"search" => {SearchTool, search}},
               max_steps: 10
             )

    assert Enum.any?(
             JidoTest.WorkflowSDKCase.errors(error),
             &(&1.message == "continuation limit exceeded")
           )

    assert length(ScriptedModel.calls(model)) == 1
    assert Server.snapshot(server).state_version == 0
  end

  defp start_quiet_agent(jido) do
    quiet_error_policy = fn _reason, _outcome -> :continue end
    start_agent!(jido, ReActAgent, error_policy: quiet_error_policy)
  end
end
