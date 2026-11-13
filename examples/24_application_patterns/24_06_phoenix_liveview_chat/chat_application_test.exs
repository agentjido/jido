Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("chat_application.ex", __DIR__)

defmodule Jido.Examples.Patterns.LiveChatTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.Examples.Patterns.LiveChat

  test "streamed multimodal chat survives client and Agent process replacement" do
    jido = start_persistent_jido()
    {:ok, address} = LiveChat.ensure_conversation(jido, "conversation-1")
    dispatch = start_stream_dispatch("conversation-1")

    attachment = %{
      media_type: "image/png",
      data_url: "data:image/png;base64,b2ZmbGluZS1pbWFnZQ=="
    }

    result =
      LiveChat.ask(jido, address, "Describe the attachment",
        attachment: attachment,
        response: "A small offline image.",
        stream_dispatch: dispatch
      )

    assert LiveChat.operation_state(result) == :committed

    signals = receive_stream([])

    assert Enum.map(signals, & &1.type) == [
             "jido.ai.model.stream.started",
             "jido.ai.model.stream.chunk",
             "jido.ai.model.stream.chunk",
             "jido.ai.model.stream.chunk",
             "jido.ai.model.stream.chunk",
             "jido.ai.model.stream.completed"
           ]

    assert Enum.map(signals, & &1.data.sequence) == Enum.to_list(0..5)

    assert {:ok,
            [
              %{role: :user, text: "Describe the attachment", attachments: [attachment_view]},
              %{role: :assistant, text: "A small offline image.", attachments: []}
            ]} = LiveChat.history(jido, address)

    assert attachment_view.attached?

    {:ok, first_server} = Jido.resolve_agent(jido, address)
    assert :ok = Jido.stop_agent(jido, first_server)

    {:ok, ^address} = LiveChat.ensure_conversation(jido, "conversation-1")
    {:ok, second_server} = Jido.resolve_agent(jido, address)
    refute second_server == first_server

    assert {:ok, [_user, %{text: "A small offline image."}]} = LiveChat.history(jido, address)
  end

  test "a model failure is visible and does not enter public chat history" do
    jido = start_persistent_jido()
    {:ok, address} = LiveChat.ensure_conversation(jido, "conversation-failure")
    dispatch = start_stream_dispatch("conversation-failure")

    result =
      LiveChat.ask(jido, address, "Fail safely",
        fail: true,
        stream_dispatch: dispatch
      )

    assert LiveChat.operation_state(result) == :failed

    assert Enum.map(receive_stream([]), & &1.type) == [
             "jido.ai.model.stream.started",
             "jido.ai.model.stream.failed"
           ]

    assert {:ok, []} = LiveChat.history(jido, address)
  end

  test "the browser state vocabulary covers terminal and nonterminal outcomes" do
    assert LiveChat.operation_state({:error, :timeout}) == :timed_out
    assert LiveChat.operation_state({:error, :cancelled}) == :cancelled

    assert LiveChat.operation_state({:ok, turn_result(:uncertain)}) == :uncertain
    assert LiveChat.operation_state({:ok, turn_result(:waiting)}) == :waiting
  end

  defp start_persistent_jido do
    suffix = System.unique_integer([:positive])
    name = :"live_chat_#{suffix}"
    persistence = {Jido.Persistence.ETS, table: Module.concat(__MODULE__, "Store#{suffix}")}

    start_supervised!(
      {Jido, name: name, namespace: "examples/live-chat/#{suffix}", persistence: persistence},
      id: name
    )

    name
  end

  defp receive_stream(signals) do
    receive do
      %Jido.Signal{type: type} = signal
      when type in [
             "jido.ai.model.stream.started",
             "jido.ai.model.stream.chunk"
           ] ->
        receive_stream(signals ++ [signal])

      %Jido.Signal{type: type} = signal
      when type in [
             "jido.ai.model.stream.completed",
             "jido.ai.model.stream.failed"
           ] ->
        signals ++ [signal]

      {:signal, %{type: type} = signal}
      when type in [
             "jido.ai.model.stream.started",
             "jido.ai.model.stream.chunk"
           ] ->
        receive_stream(signals ++ [signal])

      {:signal, %{type: type} = signal}
      when type in [
             "jido.ai.model.stream.completed",
             "jido.ai.model.stream.failed"
           ] ->
        signals ++ [signal]
    after
      1_000 -> flunk("timed out while waiting for the terminal stream Signal")
    end
  end

  defp start_stream_dispatch(conversation_id) do
    name = Module.concat(__MODULE__, "PubSub#{System.unique_integer([:positive])}")
    start_supervised!({Phoenix.PubSub, name: name}, id: name)
    topic = "examples:live-chat:#{conversation_id}"
    :ok = Phoenix.PubSub.subscribe(name, topic)
    {:pubsub, target: name, topic: topic}
  end

  defp turn_result(status) do
    %Jido.AgentServer.TurnResult{
      turn_id: "turn-1",
      agent_address: Jido.Agent.Address.new!(namespace: "examples/live-chat", id: "conversation"),
      agent_activation_id: "activation-1",
      status: status,
      durability: :durable,
      agent_revision: 0,
      persistence_revision: 0
    }
  end
end
