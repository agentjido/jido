defmodule JidoTest.FactoryHTTP do
  @moduledoc "HTTP fixtures exercise real ReqLLM encoding, decoding, and tool continuation without a key."

  def context(handler) do
    plugin = fn request -> Req.Request.put_private(request, :factory_handler, handler) end

    %{
      stream: false,
      model: "anthropic:claude-haiku-4-5",
      llm_opts: [
        api_key: "fixture-key",
        req_http_options: [adapter: __MODULE__, plugins: [plugin], retry: false]
      ]
    }
  end

  def run(request) do
    body = request.body |> IO.iodata_to_binary() |> Jason.decode!()
    handler = Req.Request.get_private(request, :factory_handler)

    {status, response} =
      case handler.(body) do
        {status, response} -> {status, response}
        response -> {200, response}
      end

    {request, Req.Response.new(status: status, body: Jason.encode!(response))}
  end

  def text(text) do
    response([%{"type" => "text", "text" => text}], "end_turn")
  end

  def tool(name, input) do
    response(
      [%{"type" => "tool_use", "id" => "call_1", "name" => name, "input" => input}],
      "tool_use"
    )
  end

  defp response(content, stop_reason) do
    %{
      "id" => "msg_fixture",
      "type" => "message",
      "role" => "assistant",
      "model" => "claude-haiku-4-5",
      "content" => content,
      "stop_reason" => stop_reason,
      "stop_sequence" => nil,
      "usage" => %{"input_tokens" => 10, "output_tokens" => 10}
    }
  end

  def system!(jido, mode, opts \\ []) do
    alias Jido.Examples.Factory.System, as: Owner
    id = JidoTest.Case.unique_id("factory")
    {:ok, owner} = Jido.start_agent(jido, Owner, id: id)
    {:ok, _} = Owner.boot(owner, mode, input: Map.new(opts))

    {factory, conversation} =
      JidoTest.Eventually.eventually(fn ->
        factory = Jido.whereis_agent(jido, "#{id}/factory")
        conversation = Jido.whereis_agent(jido, "#{id}/conversation")
        if is_pid(factory) and is_pid(conversation), do: {factory, conversation}
      end)

    if mode == :departments do
      JidoTest.Eventually.eventually(fn ->
        Enum.all?(["research", "design", "build", "quality"], fn name ->
          is_pid(Jido.whereis_agent(jido, "#{id}/factory/#{name}"))
        end)
      end)
    else
      JidoTest.Eventually.eventually(fn ->
        Map.has_key?(state(factory).scheduler.cron, "factory_poll")
      end)
    end

    %{
      owner: owner,
      factory: factory,
      conversation: conversation,
      id: id,
      factory_id: "#{id}/factory"
    }
  end

  def state(pid), do: Jido.AgentServer.agent(pid).state
end
