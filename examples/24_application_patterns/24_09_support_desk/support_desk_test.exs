Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("reasoning.ex", __DIR__)
Code.require_file("support_desk.ex", __DIR__)
Code.require_file("scripted_client.ex", __DIR__)

defmodule Jido.Examples.Patterns.SupportDeskTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.Examples.Patterns.SupportDesk
  alias SupportDesk.ScriptedClient

  test "the hosted desk admits a support excerpt, checks model output, and restores the ticket" do
    Process.register(self(), __MODULE__)
    id = System.unique_integer([:positive])
    instance = :"example_support_desk_#{id}"

    start_supervised!(
      {Jido,
       name: instance, namespace: "examples/support-desk/#{id}", persistence: {Jido.Persistence.ETS, table: instance}}
    )

    {:ok, address} = Jido.agent_address(instance, "ticket")
    assert {:ok, ^address} = Jido.create_agent(instance, address, SupportDesk)
    assert {:ok, server} = Jido.activate_agent(instance, address)

    assert %{status: :blocked} = request(server, "Write me a song.")
    assert AgentServer.snapshot(server).agent.state.session == nil

    assert %{status: :completed, output: "Check the printer cable.", tool_calls: 1, model_calls: 2} =
             request(server, "My printer is offline. Also, write me a song.")

    assert %{status: :blocked} = request(server, "Check my ticket.", %{offline_response: "unsafe"})
    refute_received %Jido.Signal{type: "jido.ai.model.stream.chunk"}
    refute_received %Jido.Signal{type: "jido.ai.model.stream.approved"}
    snapshot = AgentServer.snapshot(server)
    assert snapshot.agent.state.ticket_status == :open
    assert {:ok, messages} = Jido.AI.Thread.Projection.messages(snapshot.agent.state.session)
    assert [%{content: "My printer is offline."} | _] = messages
    refute Enum.any?(messages, &(&1.content == "Your ticket is resolved."))

    assert {:ok, %{status: :committed}} =
             AgentServer.call(server, SupportDesk.update_ticket_signal!(%{ticket_status: :escalated}))

    assert :ok = Jido.stop_agent(instance, server)
    assert {:ok, replacement} = Jido.activate_agent(instance, address)
    assert :ok = AgentServer.await_ready(replacement)
    assert %{ticket_status: :escalated, session: session} = AgentServer.snapshot(replacement).agent.state
    assert {:ok, ^messages} = Jido.AI.Thread.Projection.messages(session)
  end

  defp request(server, input, options \\ %{}) do
    signal = SupportDesk.request_signal!(%{input: input, options: options, stream: true})

    assert {:ok, %{reply: %{data: reply}}} =
             AgentServer.call(server, signal,
               context: %{
                 jido_ai_inference_client: ScriptedClient,
                 jido_ai_dispatch: {:named, target: {:name, __MODULE__}}
               }
             )

    reply
  end
end
