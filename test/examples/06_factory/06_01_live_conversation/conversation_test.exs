defmodule JidoTest.Examples.Factory.LiveConversationTest do
  use JidoTest.Case, async: true
  @moduletag :example
  @moduletag :integration
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Factory.{LiveConversation, Model}
  alias JidoTest.FactoryHTTP, as: HTTP

  test "two live transport turns send history; duplicate input makes no request", %{jido: jido} do
    test_pid = self()

    context =
      HTTP.context(fn body ->
        send(test_pid, {:request, body})
        HTTP.text("Hello")
      end)

    agent = LiveConversation.new!()
    signal = LiveConversation.chat_signal!("pure", "First")
    assert {:ok, candidate, []} = LiveConversation.cmd(agent, signal, context: context)
    assert candidate.state.answer == "Hello"
    assert agent.state.answer == ""
    assert_receive {:request, %{"messages" => [%{"role" => "user"}]}}, 2_000

    {:ok, server} = Jido.start_agent(jido, LiveConversation)
    assert {:ok, _} = LiveConversation.chat(server, "one", "First", context: context)
    assert_receive {:request, _}
    assert {:ok, agent} = LiveConversation.chat(server, "two", "Second", context: context)
    assert_receive {:request, body}
    assert Enum.map(body["messages"], & &1["role"]) == ["user", "assistant", "user"]
    assert {:error, _} = LiveConversation.chat(server, "two", "Repeat", context: context)
    refute_receive {:request, _}
    refute inspect(agent.state) =~ "fixture-key"
    assert Server.agent(server) == agent
  end

  test "authentication failure retains safe provider details and preserves committed history", %{
    jido: jido
  } do
    {:ok, server} = Jido.start_agent(jido, LiveConversation)
    before = Server.snapshot(server)

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

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, error} =
                 LiveConversation.chat(server, "failure", "Hello", context: context)

        assert error.details.status == 401
        assert error.details.reason == :model_request_failed
        assert error.details.key_env == "ANTHROPIC_API_KEY"
        assert error.details.key_source == :option
        assert error.message =~ "API key is invalid: [REDACTED]"
        assert error.message =~ "Check llm_opts[:api_key]"
        refute inspect(error) =~ "fixture-key"
      end)

    refute log =~ "fixture-key"
    assert Server.snapshot(server) == before
  end

  test "model errors discard raw request and response fields" do
    reason =
      ReqLLM.Error.API.Request.exception(
        reason: "API key is invalid.",
        status: 401,
        request_body: "private conversation",
        response_body: "private provider data",
        headers: [{"x-api-key", "fixture-key"}]
      )

    error =
      Jido.Examples.Factory.Error.request(reason, "anthropic:claude-haiku-4-5",
        api_key: "fixture-key"
      )

    refute inspect(error) =~ "private"
    refute inspect(error) =~ "fixture-key"
    assert error.details.status == 401
  end

  test "unknown tool calls terminate at the model round limit" do
    context = HTTP.context(fn _ -> HTTP.tool("unknown_tool", %{}) end)
    assert {:error, :model_round_limit} = Model.reply([%{role: :user, content: "Hello"}], context)
  end
end
