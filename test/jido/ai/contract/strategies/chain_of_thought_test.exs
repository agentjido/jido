defmodule Jido.AI.ChainOfThoughtTest do
  use Covenant.Case, component: "jido_ai.strategies", async: false

  @moduletag obligation: [
               "jido_ai.strategies.I1",
               "jido_ai.strategies.I2",
               "jido_ai.strategies.I3",
               "jido_ai.strategies.I4"
             ]

  import Mimic

  alias Jido.AI.Reasoning.ChainOfThought
  alias Jido.AITest.ChainOfThoughtAgent
  alias Jido.Agent.Directive.Reply
  alias Jido.AgentServer

  setup :set_mimic_global
  setup :verify_on_exit!

  test "the Agent exposes one explicit Chain of Thought graph" do
    assert ChainOfThoughtAgent.reasoning() == ChainOfThought

    assert ChainOfThought.default_instructions() == """
           You are a helpful AI assistant that thinks through problems step by step.
           Return an ordered list of clear reasoning steps and one concise conclusion.
           """

    assert %Jido.Flow{
             components: %{
               "start_request" => %{kind: :call},
               "input_guard" => %{kind: :call},
               "reason" => %{kind: :invoke},
               "finalize" => %{kind: :call}
             }
           } = ChainOfThought.flow()

    assert %Jido.Flow{
             components: %{
               "project" => %{kind: :call},
               "model" => %{kind: :call},
               "output_guard" => %{kind: :call},
               "record_attempt" => %{kind: :call},
               "complete" => %{kind: :call}
             }
           } = ChainOfThought.ModelRound.flow()

    assert {:ok, %{reasoning: ChainOfThought, workflow: %Runic.Workflow{}}} =
             ChainOfThoughtAgent.preflight(%{input: "Inspect the graph."})
  end

  test "the Agent round-trips through the shared Agent authoring codec" do
    registry =
      Jido.Authoring.Registry.new!(%{
        {"jido.ai/agents/chain-of-thought", 1} => {:agent, ChainOfThoughtAgent},
        {"jido.ai/agent", 1} => {:plugin, Jido.AI.Agent.Plugin},
        {"jido.ai/reasoning/chain-of-thought", 1} => {:flow, ChainOfThought},
        {"jido.ai/schemas/chain-of-thought-agent-state", 1} => {:schema, ChainOfThoughtAgent.definition().schema}
      })

    assert {:ok, json} =
             Jido.Authoring.encode_json(ChainOfThoughtAgent.definition(),
               registry: registry,
               codec: Jido.Agent.Codec
             )

    document = Jason.decode!(json)
    assert document["definition"]["routes"] == []

    assert [
             %{
               "provider" => %{"id" => "jido.ai/agent", "vsn" => 1},
               "data" => %{
                 "reasoning" => %{
                   "id" => "jido.ai/reasoning/chain-of-thought",
                   "vsn" => 1
                 }
               }
             }
           ] = document["definition"]["plugins"]

    assert {:ok, definition} =
             Jido.Authoring.decode_json(json,
               registry: registry,
               codec: Jido.Agent.Codec
             )

    assert definition == ChainOfThoughtAgent.definition()

    assert [%{handler: %{kind: :flow, target: ChainOfThought}}] =
             definition.routes
  end

  test "one model call returns structured steps and clean correlated telemetry" do
    owner = self()
    handler_id = "jido-ai-cot-test-#{System.unique_integer([:positive])}"

    assert :ok =
             :telemetry.attach_many(
               handler_id,
               [
                 [:jido, :ai, :agent, :start],
                 [:jido, :ai, :agent, :stop],
                 [:jido, :ai, :reasoning, :start],
                 [:jido, :ai, :reasoning, :stop]
               ],
               fn event, measurements, metadata, _config ->
                 send(owner, {:telemetry, event, measurements, metadata})
               end,
               nil
             )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    expect(ReqLLM, :generate_text, fn model, context, options ->
      assert model == "openai:gpt-4o-mini"
      refute Keyword.has_key?(options, :tools)
      assert %ReqLLM.Output{type: :object} = options[:output]
      assert options[:output_validation] == :strict

      [system | _rest] = ReqLLM.Context.to_list(context)
      assert message_text(system) == ChainOfThought.default_instructions()

      {:ok,
       response(model, context, %{
         "steps" => [
           %{"number" => 1, "content" => "There are 12 boxes with 8 markers each."},
           %{"number" => 2, "content" => "The initial total is 96."},
           %{"number" => 3, "content" => "Subtracting 17 gives 79."}
         ],
         "conclusion" => "79 markers remain."
       })}
    end)

    instance = String.to_atom("jido_ai_cot_#{System.unique_integer([:positive])}")
    start_supervised!({Jido, name: instance, namespace: Atom.to_string(instance)}, id: instance)

    assert {:ok, server} = Jido.start_agent(instance, ChainOfThoughtAgent, id: "cot-agent")
    assert :ok = AgentServer.await_ready(server)

    assert {:ok, agent, [%Reply{signal: reply}]} =
             AgentServer.call(
               server,
               ChainOfThoughtAgent.request_signal!(%{
                 input:
                   "A shop has 12 boxes with 8 markers in each box. It gives away 17 markers. How many markers remain?"
               })
             )

    assert reply.data.status == :completed
    assert reply.data.output == "79 markers remain."
    assert reply.data.model_calls == 1
    assert reply.data.reasoning.method == :chain_of_thought
    assert reply.data.reasoning.steps_count == 3
    assert Enum.map(reply.data.reasoning.steps, & &1.number) == [1, 2, 3]

    messages =
      agent.state.session.thread.entries
      |> Enum.filter(&(&1.kind == :ai_message))
      |> Enum.map(& &1.payload["role"])

    assert messages == ["user", "assistant"]
    [attempt] = Jido.Thread.filter_by_kind(agent.state.session.thread, :ai_model_attempt)

    before_context =
      attempt.payload |> get_in(["context", "before"]) |> Jido.AI.Context.Snapshot.decode!()

    after_context =
      attempt.payload |> get_in(["context", "after"]) |> Jido.AI.Context.Snapshot.decode!()

    assert before_context["stage"] == "prepared"
    assert after_context["stage"] == "completed"
    assert after_context["shape"]["message_count"] == 2
    assert before_context["request"]["context"]["tools"] == []

    events = receive_events([])
    {_, _, agent_start} = find_event(events, [:jido, :ai, :agent, :start])

    {_, reasoning_measurements, reasoning_stop} =
      find_event(events, [:jido, :ai, :reasoning, :stop])

    {_, agent_measurements, agent_stop} = find_event(events, [:jido, :ai, :agent, :stop])

    assert reasoning_stop.reasoning_method == :chain_of_thought
    assert reasoning_stop.turn_id == agent_start.turn_id
    assert reasoning_stop.status == :ok
    assert reasoning_measurements.duration > 0
    assert agent_stop.status == :completed
    assert agent_measurements.model_calls == 1
    assert agent_measurements.reasoning_steps == 3
  end

  test "a model failure returns a structured failed result" do
    expect(ReqLLM, :generate_text, fn _model, _context, _options ->
      {:error, :invalid_api_key}
    end)

    assert {:ok, _agent, [%Reply{signal: reply}]} = direct_request("Fail this request.")
    assert reply.data.status == :failed
    assert reply.data.output == ""
    assert reply.data.model_calls == 1
    assert reply.data.reason_code == :model
    assert reply.data.reasoning.steps == []
  end

  defp receive_events(events) do
    receive do
      {:telemetry, event, measurements, metadata} ->
        receive_events([{event, measurements, metadata} | events])
    after
      20 -> Enum.reverse(events)
    end
  end

  defp find_event(events, name), do: Enum.find(events, &(elem(&1, 0) == name))

  defp direct_request(input) do
    agent = ChainOfThoughtAgent.instantiate!(id: "cot-direct-#{System.unique_integer([:positive])}")
    ChainOfThoughtAgent.cmd(agent, ChainOfThoughtAgent.request_signal!(%{input: input}))
  end

  defp response(model, context, object) do
    %ReqLLM.Response{
      id: "cot-response",
      model: model,
      context: context,
      object: object,
      finish_reason: :stop,
      usage: %{input_tokens: 10, output_tokens: 5}
    }
  end

  defp message_text(%ReqLLM.Message{content: content}) when is_binary(content), do: content

  defp message_text(%ReqLLM.Message{content: content}) when is_list(content) do
    Enum.map_join(content, "", fn
      %{type: :text, text: text} -> text
      _part -> ""
    end)
  end
end
