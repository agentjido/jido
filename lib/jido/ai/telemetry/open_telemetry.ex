defmodule Jido.AI.Telemetry.OpenTelemetry do
  @moduledoc false

  alias Jido.AI.Telemetry.CorrelationStore

  @handler_id "jido-ai-open-telemetry"
  @req_llm_handler_id "jido-ai-req-llm-open-telemetry"

  @spec enabled?() :: boolean()
  def enabled? do
    available?() and configured?() and not noop_tracer?(tracer())
  catch
    _, _ -> false
  end

  @spec attach(keyword()) :: :ok
  def attach(opts \\ []) do
    if enabled?() do
      attach_owned_events()
      attach_req_llm(opts)
    end

    :ok
  end

  @spec with_agent_span(map(), (-> result)) :: result when result: term()
  def with_agent_span(context, fun) when is_map(context) and is_function(fun, 0) do
    case attach_agent_span(context) do
      {:ok, token} ->
        try do
          fun.()
        after
          detach(token)
        end

      :error ->
        fun.()
    end
  end

  @spec with_reasoning_span(String.t(), (-> result)) :: result when result: term()
  def with_reasoning_span(operation_id, fun)
      when is_binary(operation_id) and is_function(fun, 0) do
    with_stored_span({:otel, :reasoning, operation_id}, fun)
  end

  def handle_event([:jido, :ai, kind, :start], measurements, metadata, _config)
      when kind in [:agent, :tool] do
    key = span_key(kind, metadata)

    if key do
      parent = parent_span(kind, metadata)
      span = start_span(span_name(kind, metadata), attributes(kind, metadata, measurements), parent)

      if span do
        store_span(key, kind, span, metadata)
      end
    end

    :ok
  catch
    _, _ -> :ok
  end

  def handle_event([:jido, :ai, kind, ending], measurements, metadata, _config)
      when kind in [:agent, :tool] and ending in [:stop, :exception] do
    case span_key(kind, metadata) do
      nil -> :ok
      key -> finish_span(CorrelationStore.take(key), kind, ending, metadata, measurements)
    end
  catch
    _, _ -> :ok
  end

  def handle_event([:jido, :ai, :reasoning, :start], measurements, metadata, _config) do
    start_owned_span(:reasoning, measurements, metadata)
  catch
    _, _ -> :ok
  end

  def handle_event(
        [:jido, :ai, :reasoning, ending],
        measurements,
        metadata,
        _config
      )
      when ending in [:stop, :exception] do
    case span_key(:reasoning, metadata) do
      nil -> :ok
      key -> finish_span(CorrelationStore.take(key), :reasoning, ending, metadata, measurements)
    end
  catch
    _, _ -> :ok
  end

  defp attach_owned_events do
    case :telemetry.attach_many(
           @handler_id,
           Jido.AI.Telemetry.owned_events(),
           &__MODULE__.handle_event/4,
           nil
         ) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  defp attach_req_llm(opts) do
    req_llm_opts =
      opts
      |> Keyword.get(:req_llm, [])
      |> Keyword.put_new(:content, :none)

    case ReqLLM.OpenTelemetry.attach(@req_llm_handler_id, req_llm_opts) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
      {:error, :opentelemetry_unavailable} -> :ok
    end
  end

  defp agent_span(%{turn_id: turn_id}) when is_binary(turn_id),
    do: CorrelationStore.get({:otel, :agent, turn_id})

  defp agent_span(_context), do: nil

  defp attach_agent_span(context) do
    case agent_span(context) do
      %{span: span} ->
        current = call(:otel_ctx, :get_current, [])
        next = call(:otel_tracer, :set_current_span, [current, span])
        {:ok, call(:otel_ctx, :attach, [next])}

      _other ->
        :error
    end
  rescue
    _error -> :error
  catch
    _kind, _reason -> :error
  end

  defp with_stored_span(key, fun) do
    case attach_stored_span(key) do
      {:ok, token} ->
        try do
          fun.()
        after
          detach(token)
        end

      :error ->
        fun.()
    end
  end

  defp attach_stored_span(key) do
    case CorrelationStore.get(key) do
      %{span: span} ->
        attach_span(span)

      _other ->
        :error
    end
  rescue
    _error -> :error
  catch
    _kind, _reason -> :error
  end

  defp start_owned_span(kind, measurements, metadata) do
    key = span_key(kind, metadata)

    if key do
      parent = parent_span(kind, metadata)
      span = start_span(span_name(kind, metadata), attributes(kind, metadata, measurements), parent)

      if span do
        store_span(key, kind, span, metadata)
      end
    end

    :ok
  end

  defp parent_span(:agent, _metadata), do: nil

  defp parent_span(:tool, %{turn_id: turn_id}) when is_binary(turn_id) do
    case CorrelationStore.get({:otel, :agent, turn_id}) do
      %{span: span} -> span
      _other -> nil
    end
  end

  defp parent_span(:tool, _metadata), do: nil
  defp parent_span(:reasoning, metadata), do: parent_span(:tool, metadata)

  defp span_key(:agent, %{turn_id: turn_id}) when is_binary(turn_id),
    do: {:otel, :agent, turn_id}

  defp span_key(:tool, %{attempt_id: attempt_id}) when not is_nil(attempt_id),
    do: {:otel, :tool, attempt_id}

  defp span_key(:reasoning, %{reasoning_operation_id: operation_id})
       when is_binary(operation_id),
       do: {:otel, :reasoning, operation_id}

  defp span_key(_kind, _metadata), do: nil

  defp span_name(:agent, metadata), do: "invoke_agent #{metadata[:agent_name] || "agent"}"
  defp span_name(:tool, metadata), do: "execute_tool #{metadata[:tool_name] || "tool"}"

  defp span_name(:reasoning, metadata),
    do: "reasoning #{metadata[:reasoning_method] || "operation"}"

  defp start_span(name, attributes, nil) do
    call(:otel_tracer, :start_span, [
      call(:otel_ctx, :get_current, []),
      tracer(),
      name,
      %{kind: :internal, attributes: attributes}
    ])
  end

  defp start_span(name, attributes, parent) do
    parent_context =
      call(:otel_tracer, :set_current_span, [call(:otel_ctx, :new, []), parent])

    call(:otel_tracer, :start_span, [
      parent_context,
      tracer(),
      name,
      %{kind: :internal, attributes: attributes}
    ])
  end

  defp finish_span(nil, _kind, _ending, _metadata, _measurements), do: :ok

  defp finish_span(%{span: span} = stored, kind, ending, metadata, measurements) do
    error_type = error_type(kind, ending, metadata)
    attrs = attributes(kind, metadata, measurements) |> maybe_put("error.type", error_type)

    try do
      safely(fn -> call(:otel_span, :set_attributes, [span, attrs]) end)

      if error_type do
        safely(fn -> call(:otel_span, :set_status, [span, :error, error_type]) end)
      end

      safely(fn -> call(:otel_span, :end_span, [span]) end)
    after
      detach(Map.get(stored, :restore_context))
    end

    :ok
  end

  defp store_span(key, kind, span, metadata) do
    stored =
      case kind do
        :tool ->
          case attach_span(span) do
            {:ok, restore_context} ->
              %{
                span: span,
                metadata: metadata,
                owner: self(),
                restore_context: restore_context
              }

            :error ->
              %{span: span, metadata: metadata, owner: self()}
          end

        _other ->
          %{span: span, metadata: metadata, owner: self()}
      end

    unless CorrelationStore.put_new(key, stored, on_expire: {__MODULE__, :expire_span}) do
      detach(Map.get(stored, :restore_context))
      safely(fn -> call(:otel_span, :end_span, [span]) end)
    end

    :ok
  end

  @doc false
  @spec expire_span(term(), map()) :: :ok
  def expire_span(_key, %{span: span} = stored) do
    error_type = "jido.ai.telemetry.correlation_expired"

    safely(fn -> call(:otel_span, :set_attributes, [span, %{"error.type" => error_type}]) end)
    safely(fn -> call(:otel_span, :set_status, [span, :error, error_type]) end)
    safely(fn -> call(:otel_span, :end_span, [span]) end)

    if Map.get(stored, :owner) == self() do
      detach(Map.get(stored, :restore_context))
    end

    :ok
  end

  def expire_span(_key, _stored), do: :ok

  defp attach_span(span) do
    current = call(:otel_ctx, :get_current, [])
    next = call(:otel_tracer, :set_current_span, [current, span])
    {:ok, call(:otel_ctx, :attach, [next])}
  rescue
    _error -> :error
  catch
    _kind, _reason -> :error
  end

  defp safely(fun) do
    _result = fun.()
    :ok
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp detach(nil), do: :ok

  defp detach(token) do
    _result = call(:otel_ctx, :detach, [token])
    :ok
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp attributes(:agent, metadata, measurements) do
    %{
      "gen_ai.operation.name" => "invoke_agent",
      "gen_ai.agent.name" => metadata[:agent_name],
      "gen_ai.agent.id" => metadata[:agent_definition_id],
      "gen_ai.agent.description" => metadata[:agent_description],
      "gen_ai.agent.version" => metadata[:agent_version],
      "gen_ai.conversation.id" => metadata[:thread_id],
      "session.id" => metadata[:session_id],
      "jido.ai.agent.instance.id" => metadata[:agent_id],
      "jido.ai.agent.module" => module_name(metadata[:agent_module]),
      "jido.ai.reasoning.module" => module_name(metadata[:reasoning]),
      "jido.ai.request.id" => metadata[:request_id],
      "jido.ai.run.id" => metadata[:run_id],
      "jido.ai.session.id" => metadata[:session_id],
      "jido.ai.turn.id" => metadata[:turn_id],
      "jido.ai.status" => value(metadata[:status]),
      "jido.ai.reason.code" => value(metadata[:reason_code]),
      "jido.ai.model.calls" => measurements[:model_calls],
      "jido.ai.tool.calls" => measurements[:tool_calls],
      "jido.ai.reasoning.steps" => measurements[:reasoning_steps]
    }
    |> compact()
  end

  defp attributes(:tool, metadata, _measurements) do
    %{
      "gen_ai.operation.name" => "execute_tool",
      "gen_ai.tool.name" => metadata[:tool_name],
      "gen_ai.tool.call.id" => metadata[:tool_call_id],
      "gen_ai.tool.description" => metadata[:tool_description],
      "gen_ai.tool.type" => "function",
      "gen_ai.agent.name" => metadata[:agent_name],
      "gen_ai.conversation.id" => metadata[:thread_id],
      "session.id" => metadata[:session_id],
      "jido.ai.agent.instance.id" => metadata[:agent_id],
      "jido.ai.request.id" => metadata[:request_id],
      "jido.ai.run.id" => metadata[:run_id],
      "jido.ai.session.id" => metadata[:session_id],
      "jido.ai.turn.id" => metadata[:turn_id],
      "jido.ai.tool.action" => module_name(metadata[:action]),
      "jido.ai.tool.status" => value(metadata[:status]),
      "jido.ai.tool.retryable" => metadata[:retryable?]
    }
    |> compact()
  end

  defp attributes(:reasoning, metadata, _measurements) do
    %{
      "gen_ai.agent.name" => metadata[:agent_name],
      "gen_ai.conversation.id" => metadata[:thread_id],
      "session.id" => metadata[:session_id],
      "jido.ai.agent.instance.id" => metadata[:agent_id],
      "jido.ai.request.id" => metadata[:request_id],
      "jido.ai.run.id" => metadata[:run_id],
      "jido.ai.session.id" => metadata[:session_id],
      "jido.ai.turn.id" => metadata[:turn_id],
      "jido.ai.reasoning.module" => module_name(metadata[:reasoning]),
      "jido.ai.reasoning.method" => value(metadata[:reasoning_method]),
      "jido.ai.reasoning.status" => value(metadata[:status]),
      "jido.ai.model.request.id" => metadata[:req_llm_request_id]
    }
    |> compact()
  end

  defp error?(_kind, :exception, _metadata), do: true
  defp error?(:agent, _ending, %{status: status}), do: status in [:error, :failed]
  defp error?(:tool, _ending, %{status: status}), do: status == :error
  defp error?(:reasoning, _ending, %{status: status}), do: status == :error
  defp error?(_kind, _ending, _metadata), do: false

  defp error_type(kind, ending, metadata) do
    if error?(kind, ending, metadata) do
      metadata[:error_type]
      |> fallback(metadata[:error_code])
      |> fallback(default_error_type(kind))
      |> error_type_value()
    end
  end

  defp fallback(nil, value), do: value
  defp fallback(value, _fallback), do: value

  defp default_error_type(:agent), do: "jido.ai.agent.error"
  defp default_error_type(:tool), do: "jido.ai.tool.error"
  defp default_error_type(:reasoning), do: "jido.ai.reasoning.error"

  defp error_type_value(value) when is_atom(value) and not is_nil(value),
    do: Atom.to_string(value)

  defp error_type_value(value) when is_binary(value), do: value
  defp error_type_value(value) when is_integer(value), do: Integer.to_string(value)
  defp error_type_value(_value), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp compact(values) do
    values
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp module_name(module) when is_atom(module) and not is_nil(module), do: Atom.to_string(module)
  defp module_name(_module), do: nil
  defp value(value) when is_atom(value) and not is_nil(value), do: Atom.to_string(value)
  defp value(value) when is_binary(value) or is_integer(value) or is_boolean(value), do: value
  defp value(_value), do: nil

  defp available? do
    Enum.all?(
      [
        {:opentelemetry, :get_application_tracer, 1},
        {:otel_ctx, :get_current, 0},
        {:otel_ctx, :new, 0},
        {:otel_ctx, :attach, 1},
        {:otel_ctx, :detach, 1},
        {:otel_tracer, :set_current_span, 2},
        {:otel_tracer, :start_span, 4},
        {:otel_span, :set_attributes, 2},
        {:otel_span, :set_status, 2},
        {:otel_span, :set_status, 3},
        {:otel_span, :end_span, 1}
      ],
      fn {module, function, arity} ->
        Code.ensure_loaded?(module) and function_exported?(module, function, arity)
      end
    )
  end

  defp configured? do
    config = Application.get_env(:jido, :ai_opentelemetry, [])
    config_value(config, :enabled) != false
  end

  defp tracer, do: call(:opentelemetry, :get_application_tracer, [__MODULE__])
  defp noop_tracer?({:otel_tracer_noop, _state}), do: true
  defp noop_tracer?(:otel_tracer_noop), do: true
  defp noop_tracer?(_tracer), do: false
  defp call(module, function, arguments), do: apply(module, function, arguments)

  defp config_value(config, key) when is_list(config), do: Keyword.get(config, key)
  defp config_value(config, key) when is_map(config), do: Map.get(config, key)
  defp config_value(_config, _key), do: nil
end
