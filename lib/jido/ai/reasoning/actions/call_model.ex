defmodule Jido.AI.Reasoning.Actions.CallModel do
  @moduledoc "Calls one model and returns success or failure as graph data."

  alias Jido.AI.Context, as: AIContext
  alias Jido.AI.{Budget, InferenceClient, Telemetry, Toolset, Usage}

  use Jido.Action,
    id: "jido.ai/reasoning/actions/call-model",
    vsn: 1,
    name: "jido_ai_call_model",
    description: "Call or stream one text model",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{turn: turn, context: model_context} = params, context) do
    case Budget.before_model(turn) do
      :ok -> call_model(turn, model_context, params, context)
      {:error, budget, reason} -> budget_outcome(turn, model_context, budget, reason)
    end
  end

  defp call_model(turn, model_context, params, context) do
    model = Enum.at(turn.models, turn.model_index)
    started_at = System.system_time(:millisecond)
    stream_id = "stream_#{Jido.generate_id()}"
    :ok = Telemetry.record_agent_context(context, agent_context(turn))

    with {:ok, tools} <- model_tools(turn, Map.get(params, :tools, true)),
         {:ok, prepared_context, request} <-
           prepare_context(model_context, turn, model, tools, started_at) do
      model_call = fn ->
        if turn.stream do
          stream(request, turn, stream_id, context)
        else
          generate(request, context)
        end
      end

      result =
        case Map.get(params, :reasoning) do
          reasoning when is_map(reasoning) ->
            Telemetry.with_reasoning(context, reasoning, model_call)

          _other ->
            Telemetry.with_agent_span(context, model_call)
        end

      completed_at = System.system_time(:millisecond)
      req_llm_request_id = Telemetry.take_model_request_id(thread_id(turn))

      normalize(
        result,
        turn,
        model,
        started_at,
        completed_at,
        prepared_context,
        req_llm_request_id
      )
    end
  end

  defp prepare_context(context, turn, model, tools, started_at) do
    options =
      turn.options
      |> Map.delete(:tool_choice)
      |> Map.delete("tool_choice")
      |> apply_prompt_cache_options(model, turn)
      |> put_conversation_telemetry(turn)
      |> put_budget_timeout(turn, started_at)

    operation_id = "model-request:#{turn.model_calls + 1}"

    with {:ok, transformed} <-
           AIContext.transform(context, operation_id, fn req_llm_context ->
             %{req_llm_context | tools: tools || []}
           end),
         {:ok, prepared} <-
           AIContext.prepare(transformed,
             model: model,
             options: req_llm_options(options, turn, tools || [])
           ) do
      {:ok, prepared, prepared.request}
    end
  end

  defp req_llm_options(options, turn, tools) do
    options
    |> Map.to_list()
    |> put_tools(tools)
    |> put_option(:tool_choice, tool_choice(turn))
    |> put_output(Map.get(turn, :output_schema))
  end

  defp put_tools(options, []), do: options
  defp put_tools(options, tools), do: Keyword.put(options, :tools, tools)

  defp put_option(options, _key, nil), do: options
  defp put_option(options, key, value), do: Keyword.put(options, key, value)

  defp put_output(options, nil), do: options

  defp put_output(options, schema) when is_map(schema) do
    options
    |> Keyword.put(:output, ReqLLM.Output.object(schema))
    |> Keyword.put(:output_validation, :strict)
  end

  defp model_tools(turn, true) do
    case Toolset.definitions(turn.tools) do
      {:ok, []} -> {:ok, nil}
      result -> result
    end
  end

  defp model_tools(_turn, false), do: {:ok, nil}

  defp generate(request, context) do
    context
    |> InferenceClient.client!()
    |> then(& &1.generate_text(request.model, request.context, request.options))
  end

  defp tool_choice(turn) do
    Toolset.provider_tool_choice(turn.tool_requirement, turn.tool_rounds, turn.tools)
  end

  defp put_budget_timeout(options, turn, now) do
    case Budget.remaining_elapsed_ms(turn, now) do
      nil ->
        options

      remaining ->
        configured = field(options, :total_timeout)

        timeout =
          if is_integer(configured) and configured > 0,
            do: min(configured, remaining),
            else: remaining

        options
        |> Map.delete("total_timeout")
        |> Map.put(:total_timeout, timeout)
    end
  end

  defp budget_outcome(turn, context, budget, reason) do
    {:ok,
     %{
       turn: turn,
       context: context,
       outcome: %{
         status: :budget,
         category: :limits,
         budget: budget,
         retryable: false,
         reason: reason,
         model: Enum.at(turn.models, turn.model_index),
         usage: ReqLLM.Usage.normalize(nil)
       }
     }}
  end

  defp agent_context(turn) do
    session = Jido.Session.decode!(turn.session)

    %{
      request_id: turn.request_id,
      run_id: turn.run_id,
      session_id: session.id,
      thread_id: session.thread.id
    }
  end

  defp thread_id(turn), do: turn.session |> Jido.Session.decode!() |> then(& &1.thread.id)

  defp stream(request_data, turn, stream_id, context) do
    request = correlation(turn, stream_id, 0, System.system_time(:millisecond))
    _result = dispatch_stream_signal(context, "jido.ai.model.stream.started", request)

    sequence_counter = :atomics.new(1, [])

    on_chunk = fn chunk ->
      sequence = :atomics.add_get(sequence_counter, 1, 1)
      publish_chunk(chunk, sequence, turn, stream_id, context)
    end

    result =
      with {:ok, response} <-
             context
             |> InferenceClient.client!()
             |> then(
               & &1.stream_text(
                 request_data.model,
                 request_data.context,
                 request_data.options
               )
             ) do
        ReqLLM.StreamResponse.process_stream(response, on_chunk: on_chunk)
      end

    sequence = :atomics.get(sequence_counter, 1) + 1

    case result do
      {:ok, materialized} = success ->
        classified = ReqLLM.Response.classify(materialized)

        data =
          correlation(turn, stream_id, sequence, System.system_time(:millisecond))
          |> Map.put(:response_id, materialized.id)
          |> Map.put(:outcome, classified.type)
          |> Map.put(:finish_reason, classified.finish_reason)

        _result = dispatch_stream_signal(context, "jido.ai.model.stream.completed", data)
        success

      {:error, reason} = error ->
        publish_stream_failure(reason, turn, stream_id, sequence, context)
        error
    end
  end

  defp publish_chunk(chunk, sequence, turn, stream_id, context) do
    data =
      correlation(turn, stream_id, sequence, System.system_time(:millisecond))
      |> Map.put(:chunk, portable_chunk(chunk))

    _result = dispatch_stream_signal(context, "jido.ai.model.stream.chunk", data)
    :ok
  end

  defp publish_stream_failure(reason, turn, stream_id, sequence, context) do
    data =
      correlation(turn, stream_id, sequence, System.system_time(:millisecond))
      |> Map.put(:reason, error_message(reason))

    _result = dispatch_stream_signal(context, "jido.ai.model.stream.failed", data)
    :ok
  end

  defp dispatch_stream_signal(context, type, data) do
    case Map.get(context, :jido_ai_dispatch) do
      nil ->
        :ok

      dispatch ->
        with {:ok, signal} <- Jido.Agent.build_signal(context, type, data) do
          Jido.Signal.Dispatch.dispatch(signal, dispatch)
        end
    end
  end

  defp portable_chunk(chunk) do
    %{
      type: chunk.type,
      text: chunk.text,
      name: chunk.name,
      arguments: chunk.arguments,
      metadata: chunk.metadata
    }
  end

  defp correlation(turn, stream_id, sequence, at) do
    session = Jido.Session.decode!(turn.session)

    %{
      session_id: session.id,
      thread_id: session.thread.id,
      request_id: turn.request_id,
      run_id: turn.run_id,
      model: Enum.at(turn.models, turn.model_index),
      model_call: turn.model_calls + 1,
      model_index: turn.model_index,
      model_attempt: turn.model_attempt + 1,
      tool_rounds: turn.tool_rounds,
      stream_id: stream_id,
      sequence: sequence,
      timestamp_ms: at
    }
  end

  defp normalize(
         {:ok, response},
         turn,
         model,
         started_at,
         completed_at,
         context,
         observed_request_id
       ) do
    classified = ReqLLM.Response.classify(response)
    call_metadata = ReqLLM.Response.call_metadata(response)
    usage = Usage.normalize(ReqLLM.Response.usage(response))
    next_turn = record_call(turn, usage)

    outcome = %{
      status: :ok,
      kind: classified.type,
      finish_reason: classified.finish_reason,
      text: classified.text,
      output: Map.get(response, :object),
      tool_calls: Enum.map(classified.tool_calls, &Map.take(&1, [:id, :name, :arguments])),
      req_llm_request_id: call_metadata[:request_id] || observed_request_id,
      response_id: response.id,
      model: model,
      usage: usage,
      prompt_cache: Usage.cache_observation(turn.prompt_cache, usage, completed_at),
      started_at_ms: started_at,
      completed_at_ms: completed_at
    }

    with {:ok, completed_context} <-
           AIContext.complete(context, {:ok, response}, req_llm_request_id: outcome.req_llm_request_id) do
      {:ok, %{turn: next_turn, outcome: outcome, context: completed_context}}
    end
  end

  defp normalize(
         {:error, reason},
         turn,
         model,
         started_at,
         completed_at,
         context,
         observed_request_id
       ) do
    usage = ReqLLM.Usage.normalize(nil)
    next_turn = record_call(turn, usage)

    outcome = %{
      status: :error,
      category: category(reason),
      retryable: retryable?(reason),
      reason: error_message(reason),
      req_llm_request_id: observed_request_id,
      model: model,
      usage: usage,
      prompt_cache: Usage.cache_observation(turn.prompt_cache, usage, completed_at),
      started_at_ms: started_at,
      completed_at_ms: completed_at
    }

    with {:ok, completed_context} <-
           AIContext.complete(context, {:error, reason}, req_llm_request_id: outcome.req_llm_request_id) do
      {:ok, %{turn: next_turn, outcome: outcome, context: completed_context}}
    end
  end

  defp record_call(turn, usage) do
    turn
    |> Map.update!(:model_calls, &(&1 + 1))
    |> Map.update!(:model_attempt, &(&1 + 1))
    |> Map.update!(:usage, &Usage.add(&1, usage))
  end

  defp apply_prompt_cache_options(options, model, turn) do
    config = turn.prompt_cache

    if field(config, :enabled) == true do
      provider = model |> String.split(":", parts: 2) |> hd()
      ttl = field(config, :ttl)

      case provider do
        "openai" ->
          cache_options = if ttl, do: %{ttl: ttl}, else: %{}
          session_id = turn.session |> Jido.Session.decode!() |> Map.fetch!(:id)
          key = field(config, :key) || session_id

          options
          |> update_provider_options(:prompt_cache_key, key)
          |> maybe_put_provider_options(:prompt_cache_options, cache_options)

        "anthropic" ->
          options
          |> update_provider_options(:anthropic_prompt_cache, true)
          |> maybe_put_provider_option(:anthropic_prompt_cache_ttl, ttl)

        provider when provider in ["amazon_bedrock", "bedrock"] ->
          options
          |> update_provider_options(:prompt_cache, true)
          |> maybe_put_provider_option(:prompt_cache_ttl, ttl)

        _provider ->
          options
      end
    else
      options
    end
  end

  defp put_conversation_telemetry(options, turn) do
    thread_id = turn.session |> Jido.Session.decode!() |> then(& &1.thread.id)

    telemetry =
      case field(options, :telemetry) do
        value when is_map(value) -> value
        value when is_list(value) -> Map.new(value)
        _other -> %{}
      end

    Map.put(options, :telemetry, Map.put(telemetry, :conversation_id, thread_id))
  end

  defp update_provider_options(options, key, value) do
    provider_options = options |> field(:provider_options) |> provider_options_map()
    Map.put(options, :provider_options, Map.put(provider_options, key, value))
  end

  defp maybe_put_provider_option(options, _key, nil), do: options
  defp maybe_put_provider_option(options, key, value), do: update_provider_options(options, key, value)
  defp maybe_put_provider_options(options, _key, value) when value == %{}, do: options
  defp maybe_put_provider_options(options, key, value), do: update_provider_options(options, key, value)
  defp provider_options_map(nil), do: %{}
  defp provider_options_map(options) when is_map(options), do: options
  defp provider_options_map(options) when is_list(options), do: Map.new(options)
  defp field(nil, _key), do: nil
  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp field(_value, _key), do: nil

  @retryable_statuses [408, 409, 425, 429, 500, 502, 503, 504]
  @retryable_transport_reasons [
    :closed,
    :connect_timeout,
    :econnrefused,
    :enetdown,
    :enetunreach,
    :ehostunreach,
    :nxdomain,
    :timeout
  ]

  defp retryable?(%ReqLLM.Error.API.Timeout{}), do: true
  defp retryable?(%ReqLLM.Error.API.Request{retryable: true}), do: true

  defp retryable?(%ReqLLM.Error.API.Request{status: status})
       when status in @retryable_statuses,
       do: true

  defp retryable?(%ReqLLM.Error.API.Request{cause: cause}) when not is_nil(cause),
    do: retryable?(cause)

  defp retryable?(%ReqLLM.Error.API.Stream{cause: cause}) when not is_nil(cause),
    do: retryable?(cause)

  defp retryable?(%Req.TransportError{reason: reason}), do: retryable?(reason)
  defp retryable?(reason) when reason in @retryable_transport_reasons, do: true

  defp retryable?(reason) do
    text = reason |> inspect() |> String.downcase()

    Enum.any?(
      ["timeout", "overload", "rate_limit", "rate limit", "unavailable", "closed"],
      &String.contains?(text, &1)
    )
  end

  defp category(%ReqLLM.Error.API.Timeout{}), do: :timeout
  defp category(%ReqLLM.Error.API.Request{status: 429}), do: :rate_limit

  defp category(%ReqLLM.Error.API.Request{status: status})
       when status in [500, 502, 503, 504],
       do: :unavailable

  defp category(%ReqLLM.Error.API.Request{}), do: :provider_error
  defp category(%Req.TransportError{reason: reason}), do: category(reason)
  defp category(:timeout), do: :timeout

  defp category(reason) do
    text = reason |> inspect() |> String.downcase()

    cond do
      String.contains?(text, "timeout") -> :timeout
      String.contains?(text, "rate") -> :rate_limit
      String.contains?(text, "overload") -> :overloaded
      String.contains?(text, "unavailable") -> :unavailable
      true -> :provider_error
    end
  end

  defp error_message(%{__exception__: true} = error) do
    Exception.message(error)
  rescue
    _error -> "model request failed"
  end

  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp error_message({kind, detail}) when is_atom(kind) and (is_atom(detail) or is_binary(detail)) do
    "#{kind}: #{detail}"
  end

  defp error_message(_reason), do: "model request failed"
end
