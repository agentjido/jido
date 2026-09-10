defmodule JidoTest.Examples.LLM.ReActAgentTest do
  use JidoTest.LLMSDKCase

  alias Jido.Examples.ReActAgent
  alias Jido.Examples.ReActAgent.{ScriptedModel, SearchTool}

  @prompt "How does the OTP agent model work?"
  @query "OTP agent model"
  @answer "OTP uses isolated processes and messages."

  defmodule BlockingModel do
    @moduledoc false
    @behaviour Jido.Examples.ReActAgent.Model

    @impl true
    def complete({owner, token}, messages) when is_pid(owner) do
      send(owner, {:react_model_waiting, self(), token, messages})

      receive do
        {:release_react_model, ^token} -> {:ok, {:answer, "released"}}
      end
    end
  end

  test "one Signal runs the complete effectful ReAct Flow and commits once", %{jido: jido} do
    model =
      start_supervised!({ScriptedModel, [{:tool, "search", @query}, {:answer, @answer}]})

    search =
      start_supervised!({SearchTool, %{@query => "Agents own state and receive messages."}})

    agent = start_agent!(jido, ReActAgent)

    assert {:ok, committed} =
             ask(agent, @prompt, {ScriptedModel, model}, %{
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
             ask(agent, @prompt, {ScriptedModel, model}, %{
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
             ask(agent, @prompt, {ScriptedModel, model}, %{
               "search" => {SearchTool, search}
             })

    assert committed.state.last_answer == @answer
    assert agent_result(agent).state_version == 1
    assert length(ScriptedModel.calls(model)) == 3
    assert SearchTool.queries(search) == [@query, second_query]
  end

  test "invalid model tool choices fail before tool effects", %{jido: jido} do
    search = start_supervised!({SearchTool, %{@query => "unused"}})

    for decision <- [
          {:tool, "missing", %{query: @query}},
          {:tool, :search, @query}
        ] do
      model =
        start_supervised!(%{
          id: make_ref(),
          start: {ScriptedModel, :start_link, [[decision]]}
        })

      agent = start_quiet_agent(jido)

      assert {:error, _reason} =
               ask(agent, @prompt, {ScriptedModel, model}, %{
                 "search" => {SearchTool, search}
               })

      assert agent_result(agent).state_version == 0
      assert length(ScriptedModel.calls(model)) == 1
    end

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
             ask(
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

  test "cancelling the active Turn stops model work and keeps Agent state", %{jido: jido} do
    token = make_ref()
    owner = self()
    agent = start_quiet_agent(jido)

    request =
      Task.async(fn ->
        ask(agent, @prompt, {BlockingModel, {owner, token}}, %{})
      end)

    assert_receive {:react_model_waiting, execution, ^token, _messages}, 1_000
    assert :ok = Server.cancel(agent)
    assert {:error, _reason} = Task.await(request, 1_000)
    eventually(fn -> not Process.alive?(execution) end)

    assert %{state: %{turns: 0, messages: []}, state_version: 0} = agent_result(agent)
    fresh = start_supervised!({ScriptedModel, [{:answer, "fresh context"}]})
    assert {:ok, agent} = ask(agent, "next", {ScriptedModel, fresh}, %{})
    assert agent.state.last_answer == "fresh context"
    assert ScriptedModel.calls(fresh) == [[%{role: :user, content: "next"}]]
  end

  defp start_quiet_agent(jido) do
    quiet_error_policy = fn _reason, _outcome -> :continue end
    start_agent!(jido, ReActAgent, error_policy: quiet_error_policy)
  end

  defp ask(server, prompt, model, tools, opts \\ []) do
    max_steps = Keyword.get(opts, :max_steps, 8)

    ReActAgent.ask(server, prompt,
      input: %{max_steps: max_steps, steps_remaining: max_steps},
      context: %{model: model, tools: tools},
      timeout: Keyword.get(opts, :timeout, 5_000)
    )
  end
end
