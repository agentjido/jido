defmodule Jido.AI.Contract.CallModelTest do
  use Covenant.Case, component: "jido_ai.model_execution", async: false

  import Mimic

  alias Jido.AI.{Context, Usage}
  alias Jido.AI.Reasoning.Actions.CallModel

  setup :set_mimic_global
  setup :verify_on_exit!

  @tag obligation: ["jido_ai.model_execution.I1", "jido_ai.model_execution.I5"]
  test "model errors keep stable categories, retryability, and safe messages" do
    errors = %{
      "contract:timeout" => ReqLLM.Error.API.Timeout.exception(kind: :total, timeout: 10),
      "contract:rate" => ReqLLM.Error.API.Request.exception(reason: "limited", status: 429),
      "contract:unavailable" => ReqLLM.Error.API.Request.exception(reason: "down", status: 503),
      "contract:request" => ReqLLM.Error.API.Request.exception(reason: "bad", status: 400),
      "contract:retryable" => ReqLLM.Error.API.Request.exception(reason: "retry", retryable: true),
      "contract:cause" =>
        ReqLLM.Error.API.Request.exception(
          reason: "transport",
          cause: %Req.TransportError{reason: :econnrefused}
        ),
      "contract:stream" => ReqLLM.Error.API.Stream.exception(reason: "closed", cause: :closed),
      "contract:overloaded" => :provider_overloaded,
      "contract:string" => "plain failure",
      "contract:tuple" => {:provider, :down},
      "contract:unknown" => %{private: self()}
    }

    stub(ReqLLM, :generate_text, fn model, _context, _options ->
      {:error, Map.fetch!(errors, model)}
    end)

    expected = [
      {"contract:timeout", :timeout, true},
      {"contract:rate", :rate_limit, true},
      {"contract:unavailable", :unavailable, true},
      {"contract:request", :provider_error, false},
      {"contract:retryable", :provider_error, true},
      {"contract:cause", :provider_error, true},
      {"contract:stream", :provider_error, true},
      {"contract:overloaded", :overloaded, true},
      {"contract:string", :provider_error, false},
      {"contract:tuple", :provider_error, false},
      {"contract:unknown", :provider_error, false}
    ]

    outcomes =
      Map.new(expected, fn {model, category, retryable} ->
        assert {:ok, %{turn: next_turn, context: context, outcome: outcome}} =
                 CallModel.run(%{turn: turn(model), context: model_context()}, %{})

        assert outcome.status == :error
        assert outcome.category == category
        assert outcome.retryable == retryable
        assert is_binary(outcome.reason)
        assert outcome.model == model
        assert next_turn.model_calls == 1
        assert next_turn.model_attempt == 1
        assert context.stage == :completed
        {model, outcome}
      end)

    assert outcomes["contract:string"].reason == "plain failure"
    assert outcomes["contract:tuple"].reason == "provider: down"
    assert outcomes["contract:unknown"].reason == "model request failed"
  end

  @tag obligation: ["jido_ai.model_execution.I1", "jido_ai.model_execution.I3"]
  test "provider cache and timeout options are derived only from the portable turn" do
    owner = self()

    stub(ReqLLM, :generate_text, fn model, context, options ->
      send(owner, {:model_options, model, options})
      {:ok, response(model, context)}
    end)

    cases = [
      {"openai:model", %{enabled: true, ttl: "5m"}, %{provider_options: [existing: true]}},
      {"openai:no-ttl", %{enabled: true}, %{}},
      {"anthropic:model", %{enabled: true, ttl: "1h"}, %{}},
      {"bedrock:model", %{enabled: true, ttl: "1m"}, %{}},
      {"amazon_bedrock:model", %{enabled: true}, %{}},
      {"other:model", %{enabled: true, ttl: "5m"}, %{}},
      {"disabled:model", %{enabled: false, ttl: "5m"}, %{telemetry: [custom: true]}}
    ]

    for {model, prompt_cache, options} <- cases do
      turn =
        turn(model,
          prompt_cache: prompt_cache,
          options: Map.merge(%{"total_timeout" => 50_000}, options),
          max_elapsed_ms: 10_000
        )

      assert {:ok, %{outcome: %{status: :ok}, context: %{stage: :completed}}} =
               CallModel.run(%{turn: turn, context: model_context()}, %{})

      assert_receive {:model_options, ^model, request_options}
      assert request_options[:total_timeout] in 1..10_000

      assert get_in(request_options, [:telemetry, :conversation_id]) ==
               "session:call-model:thread"

      provider_options = Map.new(request_options[:provider_options] || %{})

      case model do
        "openai:model" ->
          assert provider_options.existing
          assert provider_options.prompt_cache_key == "session:call-model"
          assert provider_options.prompt_cache_options == %{ttl: "5m"}

        "openai:no-ttl" ->
          assert provider_options.prompt_cache_key == "session:call-model"
          refute Map.has_key?(provider_options, :prompt_cache_options)

        "anthropic:model" ->
          assert provider_options.anthropic_prompt_cache
          assert provider_options.anthropic_prompt_cache_ttl == "1h"

        model when model in ["bedrock:model", "amazon_bedrock:model"] ->
          assert provider_options.prompt_cache

        _other ->
          assert provider_options == %{}
      end
    end
  end

  @tag obligation: "jido_ai.model_execution.I4"
  test "stream setup returns one normal error outcome when the provider cannot start" do
    expect(ReqLLM, :stream_text, fn _model, _context, _options -> {:error, :closed} end)

    assert {:ok, %{outcome: outcome, context: context}} =
             CallModel.run(
               %{turn: turn("contract:stream-start", stream: true), context: model_context()},
               %{}
             )

    assert outcome.status == :error
    assert outcome.retryable
    assert outcome.reason == "closed"
    assert context.stage == :completed
  end

  defp turn(model, overrides \\ []) do
    session = Jido.Session.new(id: "session:call-model", now: 1)

    %{
      models: [model],
      model_index: 0,
      model_calls: 0,
      model_attempt: 0,
      max_model_calls: 20,
      started_at_ms: System.system_time(:millisecond),
      max_elapsed_ms: nil,
      max_input_tokens: nil,
      max_output_tokens: nil,
      max_total_tokens: nil,
      max_total_cost: nil,
      options: %{},
      prompt_cache: %{enabled: false},
      session: Jido.Session.encode(session),
      request_id: "request-1",
      run_id: "run-1",
      stream: false,
      tools: [],
      tool_requirement: :optional,
      tool_rounds: 0,
      output_schema: nil,
      usage: Usage.zero()
    }
    |> Map.merge(Map.new(overrides))
  end

  defp model_context do
    {:ok, context} = Context.new(ReqLLM.Context.new([ReqLLM.Context.user("contract")]))
    context
  end

  defp response(model, context) do
    %ReqLLM.Response{
      id: "response-1",
      model: model,
      context: context,
      finish_reason: :stop,
      message: ReqLLM.Context.assistant("done"),
      usage: %{input_tokens: 1, output_tokens: 1}
    }
  end
end
