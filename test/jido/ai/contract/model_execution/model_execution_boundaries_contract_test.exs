defmodule Jido.AI.Contract.ModelExecutionBoundariesTest do
  use Covenant.Case, component: "jido_ai.model_execution", async: true

  alias Jido.AI.{Budget, Context, Usage}
  alias Jido.AI.Context.Snapshot

  @tag obligation: "jido_ai.model_execution.I2"
  test "budget helpers report each configured limit and remaining request time" do
    base = %{
      started_at_ms: 100,
      max_elapsed_ms: 50,
      model_calls: 0,
      max_model_calls: 2,
      max_input_tokens: 10,
      max_output_tokens: 20,
      max_total_tokens: 30,
      max_total_cost: 1.0,
      max_tool_rounds: 3,
      max_tool_calls: 4,
      usage: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, total_cost: 0.0}
    }

    assert Budget.remaining_elapsed_ms(base, 120) == 30
    assert Budget.remaining_elapsed_ms(%{}, 120) == nil

    assert Budget.summary(base, 120) == %{
             elapsed_ms: 20,
             limits: %{
               elapsed_ms: 50,
               model_calls: 2,
               tool_rounds: 3,
               tool_calls: 4,
               input_tokens: 10,
               output_tokens: 20,
               total_tokens: 30,
               total_cost: 1.0
             }
           }

    assert {:error, :elapsed_ms, "maximum elapsed time reached"} = Budget.resources(base, 150)

    assert {:error, :input_tokens, "maximum input tokens reached"} =
             Budget.resources(put_in(base, [:usage, :input_tokens], 10), 120)

    assert {:error, :output_tokens, "maximum output tokens reached"} =
             Budget.resources(put_in(base, [:usage, :output_tokens], 20), 120)

    assert {:error, :total_tokens, "maximum total tokens reached"} =
             Budget.resources(put_in(base, [:usage, :total_tokens], 30), 120)

    assert {:error, :total_cost, "maximum total cost reached"} =
             Budget.resources(put_in(base, [:usage, :total_cost], 1.0), 120)

    assert :ok = Budget.resources(%{base | usage: %{input_tokens: :unknown}}, 120)
  end

  @tag obligation: ["jido_ai.model_execution.I4", "jido_ai.model_execution.I5"]
  test "Context enforces an idempotent open, prepared, and completed lifecycle" do
    assert is_map(Context.schema())
    assert {:error, :invalid_req_llm_context} = Context.new(:invalid)

    request = ReqLLM.Context.new([ReqLLM.Context.user("hello")])
    assert {:ok, context} = Context.new(request, %{id: "context-contract", metadata: %{source: "test"}})
    assert {:error, :invalid_context} = Context.validate(:invalid)

    invalid_options = %{context | request: %{context.request | options: %{temperature: 0}}}
    assert {:error, [%Zoi.Error{path: [:request, :options]}]} = Context.validate(invalid_options)

    invalid_request = %{context | request: %{context.request | context: :invalid}}
    assert {:error, :invalid_req_llm_context} = Context.validate(invalid_request)

    assert {:error, :context_operation_id_required} = Context.transform(context, "", & &1)

    assert {:error, :transform_failed} =
             Context.transform(context, "error", fn _request -> {:error, :transform_failed} end)

    assert {:error, :invalid_req_llm_context} =
             Context.transform(context, "invalid", fn _request -> :invalid end)

    assert {:error, {:context_transform_failed, %RuntimeError{message: "transform failed"}}} =
             Context.transform(context, "raise", fn _request -> raise "transform failed" end)

    assert {:ok, transformed} =
             Context.transform(context, "append-system", fn req_context ->
               {:ok, %{req_context | messages: [ReqLLM.Context.system("system") | req_context.messages]}}
             end)

    assert {:ok, ^transformed} = Context.transform(transformed, "append-system", fn _ -> :invalid end)
    assert {:error, :model_required} = Context.prepare(transformed, [])
    assert {:error, :invalid_req_llm_options} = Context.prepare(transformed, model: "contract:model", options: %{})
    assert {:error, :invalid_context_request} = Context.prepare(transformed, %{})
    assert {:error, :context_not_prepared} = Context.complete(transformed, {:error, :failed})

    assert {:ok, prepared} =
             Context.prepare(transformed, model: "contract:model", options: [temperature: 0])

    assert {:ok, ^prepared} =
             Context.prepare(prepared, model: "contract:model", options: [temperature: 0])

    assert {:error, :context_already_prepared} =
             Context.prepare(prepared, model: "other:model", options: [])

    assert {:error, :context_not_open} = Context.transform(prepared, "late", & &1)
    assert {:error, :invalid_req_llm_result} = Context.complete(prepared, :invalid)

    assert {:ok, completed} =
             Context.complete(prepared, {:error, :provider_down}, req_llm_request_id: "request-1")

    assert {:ok, ^completed} =
             Context.complete(completed, {:error, :provider_down}, req_llm_request_id: "ignored")

    assert {:error, :context_already_completed} = Context.complete(completed, {:error, :other})
    assert {:error, :context_already_completed} = Context.prepare(completed, model: "contract:model")

    identity = Context.identity_document(completed)
    assert identity.stage == :completed
    refute Map.has_key?(identity, :captured_at_ms)
    assert Runic.Identity.Projectable.identity_document(completed) == identity
  end

  @tag obligation: ["jido_ai.model_execution.I4", "jido_ai.model_execution.I5"]
  test "snapshots safely expose full, redacted, and invalid result shapes" do
    assert is_map(Snapshot.schema())
    assert {:error, :invalid_context_snapshot} = Snapshot.decode(:invalid)
    assert {:error, :invalid_context_snapshot} = Snapshot.decode(Jason.encode!(%{"version" => 1}))
    assert {:error, %Jason.DecodeError{}} = Snapshot.decode("not-json")

    assert_raise ArgumentError, ~r/invalid context snapshot/, fn ->
      Snapshot.decode!(Jason.encode!(%{"version" => 2}))
    end

    tool_call = ReqLLM.ToolCall.new("call-1", "lookup", Jason.encode!(%{id: "42"}))

    message = %ReqLLM.Message{
      ReqLLM.Context.assistant("", tool_calls: [tool_call])
      | reasoning_details: [
          %ReqLLM.Message.ReasoningDetails{
            text: "reasoning",
            signature: "signature",
            provider: :test,
            format: "contract",
            index: 0
          }
        ]
    }

    request = ReqLLM.Context.new([ReqLLM.Context.user("secret"), message])

    metadata = %{
      function: fn -> :ok end,
      pid: self(),
      reference: make_ref(),
      api_key: "secret-key",
      nested: %{{:tuple, 1} => :value}
    }

    assert {:ok, context} = Context.new(request, metadata: metadata)
    assert {:ok, prepared} = Context.prepare(context, model: "contract:model", options: [api_key: "secret"])

    none = Context.snapshot(prepared, content: :none)
    redacted = Context.snapshot(prepared, content: :redacted)
    full = Context.snapshot(prepared, content: :full)

    assert none.request.options.api_key == "[REDACTED]"
    refute Map.has_key?(hd(none.request.context.messages), :content)
    assert hd(redacted.request.context.messages).content == "[REDACTED]"
    assert hd(full.request.context.messages).content != "[REDACTED]"
    assert full.metadata.function == "[FUNCTION]"
    assert full.metadata.pid == "[PID]"
    assert full.metadata.reference == "[REFERENCE]"
    assert full.metadata.api_key == "[REDACTED]"

    diff = Context.diff(none, full)
    assert diff.request_changed
    assert diff.messages_changed
    assert diff.before.stage == :prepared
    assert diff.after.stage == :prepared

    assert_raise ArgumentError, "context has no :open snapshot", fn ->
      Context.snapshot(prepared, stage: :open)
    end

    assert {:ok, failed} =
             Context.complete(prepared, {:error, RuntimeError.exception("provider failed")}, %{
               req_llm_request_id: "request-2"
             })

    error_full = failed |> Context.snapshot(content: :full) |> Snapshot.to_map()
    error_redacted = failed |> Context.snapshot(content: :redacted) |> Snapshot.to_map()
    assert error_full.response.error.message == "provider failed"
    assert error_full.response.error.__exception__
    assert error_redacted.response.error.type =~ "RuntimeError"
    assert error_redacted.response.call_metadata.request_id == "request-2"
  end

  @tag obligation: ["jido_ai.model_execution.I4", "jido_ai.model_execution.I5"]
  test "snapshots keep fallback request and response shapes portable" do
    request = ReqLLM.Context.new([ReqLLM.Context.user("edge")])
    assert {:ok, context} = Context.new(request, metadata: %{bits: <<1::1>>})
    assert Context.snapshot(context, stage: :open).stage == :open

    assert {:ok, prepared} =
             Context.prepare(context,
               model: "contract:model",
               options: [output: %{kind: :custom}]
             )

    invalid_tool = %ReqLLM.Tool{
      name: "invalid",
      description: "invalid schema",
      parameter_schema: :invalid,
      compiled: nil,
      callback: fn _input -> {:ok, %{}} end,
      strict: false,
      provider_options: %{}
    }

    tool_call = %{id: "call-map", name: "map_tool", arguments: %{value: 1}}
    assistant = %{ReqLLM.Context.assistant("") | tool_calls: [tool_call]}

    request_context = %{
      prepared.request.context
      | messages: [assistant],
        tools: [
          %{name: "map_tool", description: "map tool", strict: false, parameter_schema: %{}},
          invalid_tool,
          :invalid_tool
        ]
    }

    edge = %{prepared | request: %{prepared.request | context: request_context}}
    edge_redacted = Context.snapshot(edge, content: :redacted)
    edge_full = Context.snapshot(edge, content: :full)

    assert edge_redacted.request.options.output == %{kind: :custom}

    assert hd(edge_redacted.request.context.messages).tool_calls == [
             %{
               id: "call-map",
               name: "map_tool",
               arguments_digest: Context.term_digest(%{value: 1}),
               metadata: %{}
             }
           ]

    assert Enum.at(edge_redacted.request.context.tools, 1) == %{
             name: "invalid",
             description: "invalid schema",
             strict: false
           }

    assert Enum.at(edge_redacted.request.context.tools, 2).name == nil
    assert Enum.at(edge_full.request.context.tools, 0).name == "map_tool"
    assert edge_full.metadata.bits == inspect(<<1::1>>)

    response = %ReqLLM.Response{
      id: "response-edge",
      model: "contract:model",
      context: nil,
      message: ReqLLM.Context.assistant("done"),
      object: %{answer: 42},
      finish_reason: :stop,
      provider_meta: %{}
    }

    assert {:ok, completed} =
             Context.complete(prepared, {:ok, response}, req_llm_request_id: "")

    response_full = Context.snapshot(completed, content: :full)
    response_redacted = Context.snapshot(completed, content: :redacted)
    assert response_full.response.output == %{answer: 42}
    assert response_full.response.context == nil
    assert response_redacted.response.output == "[REDACTED]"
  end

  @tag obligation: "jido_ai.model_execution.I3"
  test "usage combines cache semantics and records cache write expiry for every TTL form" do
    first =
      Usage.add(Usage.zero(), %{
        input_tokens: 10,
        cache_write_tokens: 5,
        cache_write_tokens_by_ttl: %{"1s" => 2},
        input_includes_cached: true
      })

    combined =
      Usage.add(first, %{
        input_tokens: 5,
        cache_write_tokens: 7,
        cache_write_tokens_by_ttl: %{"1s" => 3, "1m" => 4},
        input_includes_cached: false
      })

    assert combined.cache_write_tokens_by_ttl == %{"1m" => 4, "1s" => 5}
    assert combined.input_includes_cached == :mixed

    observation =
      Usage.cache_observation(
        %{enabled: true, ttl: "1h"},
        %{input_tokens: 3, cache_write_tokens: 3},
        1_000
      )

    assert observation.requested

    assert [%{ttl: "1h", ttl_ms: 3_600_000, estimated_expires_at_ms: 3_601_000}] =
             observation.writes

    for {ttl, expected} <- [{0, 0}, {"1ms", 1}, {"1s", 1_000}, {"1m", 60_000}, {"1h", 3_600_000}] do
      observed =
        Usage.cache_observation(
          %{enabled: true, ttl: ttl},
          %{input_tokens: 1, cache_write_tokens: 1},
          10
        )

      assert [%{ttl_ms: ^expected}] = observed.writes
    end

    invalid =
      Usage.cache_observation(
        %{enabled: true, ttl: "later"},
        %{input_tokens: 1, cache_write_tokens: 1},
        10
      )

    assert [%{ttl_ms: nil, estimated_expires_at_ms: nil}] = invalid.writes
  end
end
