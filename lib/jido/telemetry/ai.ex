defmodule Jido.Telemetry.AI do
  @moduledoc """
  The public observability API for AI Agent execution.

  Jido AI emits semantic Agent, reasoning, and tool events under
  `[:jido, :ai]`. Model request, streaming, token, cache, and cost data remain
  owned by ReqLLM. Use `events/0` to get the complete event inventory and
  `metrics/0` to configure a `Telemetry.Metrics` reporter.

  Semantic logging consumes the same events. Configure it with:

      config :jido, :ai_telemetry,
        semantic_log_mode: :interesting,
        semantic_slow_threshold_ms: 1_000,
        correlation_ttl_ms: 3_600_000,
        correlation_sweep_interval_ms: 60_000

  Supported log modes are `:off`, `:errors`, `:interesting`, and `:all`.
  Prompts, model output, reasoning text, tool arguments, tool results, Agent
  state, and raw errors are not logged.

  Any mode other than `:off` logs a warning when a model response breaks an
  output limit (`[:jido, :ai, :limit, :exceeded]`) and when a request ends
  `:blocked` with reason code `:limits` or `:output`.

  If the optional `opentelemetry_api` dependency and a host-managed SDK are
  active, Jido AI maps Agent, reasoning, and tool operations to portable
  OpenTelemetry GenAI spans and enables ReqLLM's model span bridge. Standard
  `gen_ai.*`, `session.id`, and `error.type` attributes carry portable meaning.
  Runtime-specific correlation stays under `jido.ai.*`. Jido AI does not add
  backend-specific attributes, start an SDK, or configure sampling and export.
  """

  require Logger

  alias Jido.Telemetry.AI.{CorrelationStore, OpenTelemetry}

  @request_type "jido.ai.request"
  @runtime_handler_id "jido-ai-runtime-telemetry"
  @semantic_handler_id "jido-ai-semantic-logger"
  @reasoning_scope_key {__MODULE__, :reasoning_operation_id}
  @log_modes [:off, :errors, :interesting, :all]

  @agent_events [
    [:jido, :ai, :agent, :start],
    [:jido, :ai, :agent, :stop],
    [:jido, :ai, :agent, :exception]
  ]

  @tool_events [
    [:jido, :ai, :tool, :start],
    [:jido, :ai, :tool, :stop],
    [:jido, :ai, :tool, :exception]
  ]

  @reasoning_events [
    [:jido, :ai, :reasoning, :start],
    [:jido, :ai, :reasoning, :stop],
    [:jido, :ai, :reasoning, :exception]
  ]

  @correlation_events [
    [:jido, :ai, :telemetry, :correlation, :cleanup]
  ]

  @limit_events [
    [:jido, :ai, :limit, :exceeded]
  ]

  @owned_events @agent_events ++ @reasoning_events ++ @tool_events

  @model_log_events [
    [:req_llm, :request, :start],
    [:req_llm, :request, :stop],
    [:req_llm, :request, :exception]
  ]

  @runtime_events [
    [:jido, :agent_server, :turn, :start],
    [:jido, :agent_server, :turn, :stop],
    [:jido, :agent_server, :turn, :exception],
    [:jido, :action, :start],
    [:jido, :action, :stop],
    [:jido, :action, :exception]
  ]

  @model_correlation_events [[:req_llm, :request, :start]]

  @typedoc "A telemetry event name."
  @type event_name :: [atom(), ...]

  @doc "Returns the complete AI Agent event inventory, including lower layers."
  @spec events() :: [event_name()]
  def events do
    (@owned_events ++
       @limit_events ++
       @correlation_events ++
       @runtime_events ++
       Jido.Telemetry.Exec.event_names() ++
       Runic.Runner.Telemetry.event_names() ++ ReqLLM.Telemetry.events())
    |> Enum.uniq()
  end

  @doc false
  @spec owned_events() :: [event_name()]
  def owned_events, do: @owned_events

  @doc "Returns low-cardinality metrics for Agent, tool, and model operations."
  @spec metrics() :: [Telemetry.Metrics.t()]
  def metrics do
    [
      Telemetry.Metrics.counter("jido.ai.agent.stop.count",
        tags: [:status, :reasoning_name]
      ),
      Telemetry.Metrics.summary("jido.ai.agent.stop.duration",
        tags: [:status, :reasoning_name],
        unit: {:native, :millisecond}
      ),
      Telemetry.Metrics.counter("jido.ai.reasoning.stop.count",
        tags: [:reasoning_name, :reasoning_method, :status]
      ),
      Telemetry.Metrics.summary("jido.ai.reasoning.stop.duration",
        tags: [:reasoning_name, :reasoning_method, :status],
        unit: {:native, :millisecond}
      ),
      Telemetry.Metrics.counter("jido.ai.limit.exceeded.count", tags: [:limit]),
      Telemetry.Metrics.counter("jido.ai.tool.stop.count", tags: [:status, :tool_name]),
      Telemetry.Metrics.summary("jido.ai.tool.stop.duration",
        tags: [:status, :tool_name],
        unit: {:native, :millisecond}
      ),
      Telemetry.Metrics.counter("jido.ai.model.request.count",
        event_name: [:req_llm, :request, :stop],
        tags: [:provider, :model, :operation],
        tag_values: &model_tag_values/1
      ),
      Telemetry.Metrics.counter("jido.ai.model.request.exception.count",
        event_name: [:req_llm, :request, :exception],
        tags: [:provider, :model, :operation],
        tag_values: &model_tag_values/1
      ),
      Telemetry.Metrics.summary("jido.ai.model.request.duration",
        event_name: [:req_llm, :request, :stop],
        measurement: :duration,
        tags: [:provider, :model, :operation],
        tag_values: &model_tag_values/1,
        unit: {:native, :millisecond}
      ),
      Telemetry.Metrics.sum("jido.ai.telemetry.correlation.expired",
        event_name: [:jido, :ai, :telemetry, :correlation, :cleanup],
        measurement: :expired
      ),
      Telemetry.Metrics.last_value("jido.ai.telemetry.correlation.size",
        event_name: [:jido, :ai, :telemetry, :correlation, :cleanup],
        measurement: :size
      )
    ] ++ usage_metrics()
  end

  @doc "Attaches one handler to the complete event inventory."
  @spec attach(term(), :telemetry.handler_function(), term()) :: :ok | {:error, :already_exists}
  def attach(handler_id, handler, config \\ nil) when is_function(handler, 4) do
    :telemetry.attach_many(handler_id, events(), handler, config)
  end

  @doc "Returns true when optional OpenTelemetry mapping is active."
  @spec open_telemetry?() :: boolean()
  def open_telemetry?, do: OpenTelemetry.enabled?()

  @doc "Attaches the vendor-neutral Agent, reasoning, tool, and ReqLLM OpenTelemetry bridges."
  @spec attach_open_telemetry(keyword()) :: :ok
  def attach_open_telemetry(opts \\ []), do: OpenTelemetry.attach(@owned_events, opts)

  @doc false
  @spec attach_default_handlers() :: :ok
  def attach_default_handlers do
    attach_once(
      @runtime_handler_id,
      @runtime_events ++ @model_correlation_events,
      &__MODULE__.handle_runtime_event/4
    )

    attach_once(
      @semantic_handler_id,
      @owned_events ++ @limit_events ++ @model_log_events,
      &__MODULE__.handle_semantic_event/4
    )

    attach_open_telemetry(configured_open_telemetry_options())
  end

  @doc false
  @spec with_agent_span(map(), (-> result)) :: result when result: term()
  def with_agent_span(context, fun), do: OpenTelemetry.with_agent_span(context, fun)

  @doc false
  @spec with_reasoning(map(), map(), (-> result)) :: result when result: term()
  def with_reasoning(context, reasoning, fun)
      when is_map(context) and is_map(reasoning) and is_function(fun, 0) do
    operation_id = "reasoning_#{Jido.Id.uuid7()}"
    metadata = reasoning_metadata(context, reasoning, operation_id)
    conversation_id = metadata[:thread_id]
    started_at = System.monotonic_time()
    previous_operation = Process.get(@reasoning_scope_key)
    Process.put(@reasoning_scope_key, operation_id)

    if is_binary(conversation_id) do
      CorrelationStore.put({:reasoning_conversation, conversation_id}, operation_id)
    end

    :telemetry.execute(
      [:jido, :ai, :reasoning, :start],
      %{monotonic_time: started_at, system_time: System.system_time()},
      metadata
    )

    try do
      result = OpenTelemetry.with_reasoning_span(operation_id, fun)
      duration = max(System.monotonic_time() - started_at, 0)

      :telemetry.execute(
        [:jido, :ai, :reasoning, :stop],
        %{duration: duration},
        metadata
        |> Map.put(:status, reasoning_status(result))
        |> Map.merge(reasoning_result_metadata(result, operation_id))
      )

      result
    catch
      kind, reason ->
        duration = max(System.monotonic_time() - started_at, 0)

        :telemetry.execute(
          [:jido, :ai, :reasoning, :exception],
          %{duration: duration},
          metadata
          |> Map.put(:status, :error)
          |> Map.put(:error_type, reasoning_error_type(kind, reason))
        )

        CorrelationStore.take({:reasoning_request, operation_id})
        :erlang.raise(kind, reason, __STACKTRACE__)
    after
      clear_reasoning_conversation(conversation_id, operation_id)

      if previous_operation,
        do: Process.put(@reasoning_scope_key, previous_operation),
        else: Process.delete(@reasoning_scope_key)
    end
  end

  @doc false
  @spec record_agent_summary(map(), map()) :: :ok
  def record_agent_summary(context, summary) when is_map(context) and is_map(summary) do
    case Map.get(context, :turn_id) do
      turn_id when is_binary(turn_id) ->
        CorrelationStore.put({:summary, turn_id}, normalize_summary(summary))

      _other ->
        :ok
    end
  end

  @doc false
  @spec limit_exceeded(map(), atom(), map(), map()) :: :ok
  def limit_exceeded(context, limit, measurements, values)
      when is_map(context) and is_atom(limit) and is_map(measurements) and is_map(values) do
    agent = context |> Map.get(:turn_id) |> agent_context() || %{}

    metadata =
      agent
      |> Map.merge(Map.take(context, [:agent_id, :turn_id]))
      |> Map.merge(values)
      |> Map.put(:limit, limit)
      |> Map.update(:model, nil, &model_label/1)
      |> compact()

    :telemetry.execute([:jido, :ai, :limit, :exceeded], measurements, metadata)
  end

  @doc false
  @spec record_agent_context(map(), map()) :: :ok
  def record_agent_context(context, values) when is_map(context) and is_map(values) do
    case {Map.get(context, :turn_id), Map.get(context, :turn_id) |> agent_context()} do
      {turn_id, current} when is_binary(turn_id) and is_map(current) ->
        updates =
          values
          |> Map.take([:request_id, :run_id, :session_id, :thread_id])
          |> compact()

        CorrelationStore.put({:agent, turn_id}, Map.merge(current, updates))

      _other ->
        :ok
    end
  end

  @doc false
  @spec record_tool_calls(map(), map()) :: :ok
  def record_tool_calls(context, calls) when is_map(context) and is_map(calls) do
    case Map.get(context, :turn_id) do
      turn_id when is_binary(turn_id) ->
        calls =
          calls
          |> Enum.flat_map(fn
            {execution_name, %{id: id, name: name} = call}
            when is_binary(execution_name) and is_binary(id) and id != "" and is_binary(name) ->
              [{execution_name, Map.take(call, [:id, :name, :description, :action])}]

            _invalid ->
              []
          end)
          |> Map.new()

        CorrelationStore.put({:tool_calls, turn_id}, calls)

      _other ->
        :ok
    end
  end

  @doc false
  def handle_runtime_event([:jido, :agent_server, :turn, ending], measurements, metadata, _config)
      when ending in [:start, :stop, :exception] do
    if ai_turn?(metadata) do
      bridge_agent_event(ending, measurements, metadata)
    end

    :ok
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  def handle_runtime_event([:jido, :action, ending], measurements, metadata, _config)
      when ending in [:start, :stop, :exception] do
    if ai_tool_action?(metadata) do
      bridge_tool_event(ending, measurements, metadata)
    end

    :ok
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  def handle_runtime_event([:req_llm, :request, :start], _measurements, metadata, _config) do
    conversation_id = req_llm_conversation_id(metadata)

    if is_binary(conversation_id) and is_binary(metadata[:request_id]) do
      CorrelationStore.put({:model_request, conversation_id}, metadata[:request_id])

      case CorrelationStore.get({:reasoning_conversation, conversation_id}) do
        operation_id when is_binary(operation_id) ->
          CorrelationStore.put({:reasoning_request, operation_id}, metadata[:request_id])

        _other ->
          :ok
      end
    end

    case {Process.get(@reasoning_scope_key), metadata[:request_id]} do
      {operation_id, request_id} when is_binary(operation_id) and is_binary(request_id) ->
        CorrelationStore.put({:reasoning_request, operation_id}, request_id)

      _other ->
        :ok
    end
  end

  def handle_runtime_event(_event, _measurements, _metadata, _config), do: :ok

  @doc false
  @spec take_model_request_id(String.t()) :: String.t() | nil
  def take_model_request_id(conversation_id) when is_binary(conversation_id) do
    CorrelationStore.take({:model_request, conversation_id})
  end

  def take_model_request_id(_conversation_id), do: nil

  @doc false
  def handle_semantic_event(event, measurements, metadata, _config) do
    mode = semantic_log_mode()

    if log_semantic?(mode, event, measurements, metadata) do
      fields = log_fields(event, measurements, metadata)

      message =
        "[jido.ai.semantic] event=#{event |> Enum.drop(1) |> Enum.join(".")} " <>
          format_fields(fields)

      if semantic_error?(event, metadata),
        do: Logger.warning(message),
        else: Logger.debug(message)
    end

    :ok
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp bridge_agent_event(:start, measurements, metadata) do
    ai_metadata = agent_metadata(metadata)
    CorrelationStore.put({:agent, metadata.turn_id}, ai_metadata)
    :telemetry.execute([:jido, :ai, :agent, :start], measurements, ai_metadata)
  end

  defp bridge_agent_event(ending, measurements, metadata) do
    summary =
      CorrelationStore.take({:summary, metadata.turn_id}) ||
        %{measurements: %{}, metadata: %{}}

    started = CorrelationStore.get({:agent, metadata.turn_id}) || agent_metadata(metadata)

    ai_metadata =
      started
      |> Map.merge(agent_terminal_metadata(ending, metadata))
      |> Map.merge(summary.metadata)

    measurements = Map.merge(measurements, summary.measurements)
    :telemetry.execute([:jido, :ai, :agent, ending], measurements, ai_metadata)
    CorrelationStore.take({:agent, metadata.turn_id})
    CorrelationStore.take({:tool_calls, metadata.turn_id})
    :ok
  end

  defp bridge_tool_event(ending, measurements, metadata) do
    agent = CorrelationStore.get({:agent, metadata.turn_id}) || %{}
    tool_call = registered_tool_call(metadata)
    action = tool_call[:action] || metadata[:action]

    ai_metadata =
      agent
      |> Map.take([
        :agent_id,
        :agent_definition_id,
        :agent_description,
        :agent_module,
        :agent_name,
        :agent_version,
        :reasoning,
        :reasoning_name,
        :request_id,
        :run_id,
        :session_id,
        :thread_id,
        :turn_id,
        :trace_id,
        :span_id,
        :parent_span_id
      ])
      |> Map.merge(%{
        action: action,
        tool_name: tool_call[:name] || metadata[:action_name],
        node_name: metadata[:node_name],
        activation_id: metadata[:activation_id],
        attempt_id: metadata[:attempt_id],
        attempt: metadata[:attempt],
        status: tool_status(ending, metadata),
        tool_call_id: tool_call[:id],
        tool_description: tool_call[:description] || action_description(action),
        error_type: metadata[:error_type],
        retryable?: metadata[:retryable?]
      })
      |> compact()

    :telemetry.execute([:jido, :ai, :tool, ending], measurements, ai_metadata)
  end

  defp reasoning_metadata(context, reasoning, operation_id) do
    agent = CorrelationStore.get({:agent, context[:turn_id]}) || %{}

    agent
    |> Map.take([
      :agent_id,
      :agent_definition_id,
      :agent_description,
      :agent_module,
      :agent_name,
      :agent_version,
      :reasoning,
      :reasoning_name,
      :request_id,
      :run_id,
      :session_id,
      :thread_id,
      :turn_id,
      :trace_id,
      :span_id,
      :parent_span_id
    ])
    |> Map.merge(%{
      reasoning_operation_id: operation_id,
      reasoning_method: reasoning[:method]
    })
    |> compact()
  end

  defp reasoning_status({:ok, _value}), do: :ok
  defp reasoning_status({:error, _reason}), do: :error
  defp reasoning_status(_result), do: :unknown

  defp reasoning_result_metadata(result, operation_id) do
    request_id =
      CorrelationStore.take({:reasoning_request, operation_id}) || response_request_id(result)

    %{
      req_llm_request_id: request_id,
      error_type: reasoning_result_error_type(result)
    }
    |> compact()
  end

  defp response_request_id({:ok, %ReqLLM.Response{} = response}),
    do: ReqLLM.Response.call_metadata(response)[:request_id]

  defp response_request_id(_result), do: nil

  defp clear_reasoning_conversation(conversation_id, operation_id)
       when is_binary(conversation_id) do
    key = {:reasoning_conversation, conversation_id}

    case CorrelationStore.take(key) do
      ^operation_id -> :ok
      nil -> :ok
      current -> CorrelationStore.put(key, current)
    end
  end

  defp clear_reasoning_conversation(_conversation_id, _operation_id), do: :ok

  defp reasoning_result_error_type({:error, %{type: type}}) when is_atom(type) or is_binary(type),
    do: type

  defp reasoning_result_error_type({:error, %{__struct__: module}}) when is_atom(module),
    do: module

  defp reasoning_result_error_type({:error, type}) when is_atom(type), do: type

  defp reasoning_result_error_type({:error, {type, _details}}) when is_atom(type), do: type
  defp reasoning_result_error_type({:error, _reason}), do: :reasoning_error
  defp reasoning_result_error_type(_result), do: nil

  defp reasoning_error_type(:error, %{__struct__: module}) when is_atom(module), do: module
  defp reasoning_error_type(kind, _reason) when kind in [:error, :exit, :throw], do: kind

  defp agent_metadata(metadata) do
    agent_module = metadata[:agent_module]
    definition = agent_definition(agent_module)
    reasoning = reasoning(agent_module)

    %{
      agent_id: metadata[:agent_id],
      agent_definition_id: definition[:id],
      agent_description: definition[:description],
      agent_module: agent_module,
      agent_name: metadata[:agent_name] || agent_name(agent_module),
      agent_version: definition[:vsn] |> version(),
      reasoning: reasoning,
      reasoning_name: reasoning_name(reasoning),
      request_id: metadata[:signal_id],
      turn_id: metadata[:turn_id],
      trace_id: metadata[:trace_id],
      span_id: metadata[:span_id],
      parent_span_id: metadata[:parent_span_id]
    }
    |> compact()
  end

  defp agent_terminal_metadata(:exception, metadata) do
    %{
      status: :error,
      error_type: metadata[:error_type],
      error_code: metadata[:error_code]
    }
    |> compact()
  end

  defp agent_terminal_metadata(:stop, metadata) do
    %{
      status: metadata[:status],
      committed?: metadata[:committed?],
      error_type: metadata[:error_type],
      error_code: metadata[:error_code]
    }
    |> compact()
  end

  defp normalize_summary(summary) do
    usage = Map.get(summary, :usage, %{})

    measurements =
      summary
      |> Map.take([
        :model_calls,
        :tool_rounds,
        :tool_calls,
        :tool_errors,
        :retries,
        :reasoning_steps
      ])
      |> Map.merge(%{
        input_tokens: usage_value(usage, :input_tokens),
        output_tokens: usage_value(usage, :output_tokens),
        cache_read_tokens: usage_value(usage, :cache_read_tokens),
        cache_write_tokens: usage_value(usage, :cache_write_tokens),
        reasoning_tokens: usage_value(usage, :reasoning_tokens),
        total_cost: usage_value(usage, :total_cost)
      })

    metadata =
      summary
      |> Map.take([:status, :run_id, :session_id, :thread_id, :reason_code])
      |> Map.merge(limit_reason(summary))
      |> compact()

    %{measurements: measurements, metadata: metadata}
  end

  defp ai_turn?(%{signal_type: @request_type, turn_id: turn_id}) when is_binary(turn_id),
    do: true

  defp ai_turn?(_metadata), do: false

  # Budget reasons are fixed strings. Other reasons can carry request data.
  defp limit_reason(%{reason_code: :limits, reason: reason}), do: %{reason: reason}
  defp limit_reason(_summary), do: %{}

  defp model_label(nil), do: nil
  defp model_label(model), do: model_name(model)

  defp agent_context(turn_id) when is_binary(turn_id),
    do: CorrelationStore.get({:agent, turn_id})

  defp agent_context(_turn_id), do: nil

  defp registered_tool_call(%{turn_id: turn_id, node_path: node_path})
       when is_binary(turn_id) and is_list(node_path) do
    execution_name = List.last(node_path)

    case CorrelationStore.get({:tool_calls, turn_id}) do
      calls when is_map(calls) -> Map.get(calls, execution_name, %{})
      _other -> %{}
    end
  end

  defp registered_tool_call(_metadata), do: %{}

  defp ai_tool_action?(%{turn_id: turn_id, component: "tools", component_kind: :parallel})
       when is_binary(turn_id) do
    not is_nil(CorrelationStore.get({:agent, turn_id}))
  end

  defp ai_tool_action?(_metadata), do: false

  defp tool_status(:exception, _metadata), do: :error
  defp tool_status(:start, _metadata), do: nil
  defp tool_status(:stop, %{outcome: :ok}), do: :ok
  defp tool_status(:stop, %{outcome: :error}), do: :error
  defp tool_status(:stop, _metadata), do: :unknown

  defp reasoning(module) when is_atom(module) and not is_nil(module) do
    if function_exported?(module, :reasoning, 0), do: module.reasoning()
  rescue
    _error -> nil
  end

  defp reasoning(_module), do: nil

  defp agent_definition(module) when is_atom(module) and not is_nil(module) do
    authoring =
      if function_exported?(module, :__jido_catalog_manifest__, 0),
        do: module.__jido_catalog_manifest__(),
        else: %{}

    case module.definition() do
      %{id: id, description: description, vsn: vsn} ->
        %{
          id: authoring[:id] || id,
          description: authoring[:description] || description,
          vsn: authoring[:vsn] || vsn
        }

      _other ->
        %{}
    end
  rescue
    _error -> %{}
  end

  defp agent_definition(_module), do: %{}

  defp agent_name(module) when is_atom(module) and not is_nil(module) do
    module.definition().name
  rescue
    _error -> nil
  end

  defp agent_name(_module), do: nil

  defp action_description(module) when is_atom(module) and not is_nil(module) do
    if function_exported?(module, :description, 0), do: module.description()
  rescue
    _error -> nil
  end

  defp action_description(_module), do: nil

  defp version(value) when is_binary(value), do: value
  defp version(value) when is_integer(value) and value > 0, do: Integer.to_string(value)
  defp version(_value), do: nil

  defp reasoning_name(module) when is_atom(module) and not is_nil(module) do
    if function_exported?(module, :name, 0), do: module.name(), else: Atom.to_string(module)
  rescue
    _error -> Atom.to_string(module)
  end

  defp reasoning_name(_module), do: nil

  defp usage_metrics do
    for key <- [
          :input_tokens,
          :output_tokens,
          :cache_read_tokens,
          :cache_write_tokens,
          :reasoning_tokens,
          :total_cost
        ] do
      Telemetry.Metrics.sum("jido.ai.model.#{key}",
        event_name: [:req_llm, :request, :stop],
        measurement: fn _measurements, metadata -> usage_value(metadata[:usage], key) end,
        tags: [:provider, :model],
        tag_values: &model_tag_values/1
      )
    end
  end

  defp usage_value(usage, key) when is_map(usage) do
    direct = Map.get(usage, key, Map.get(usage, Atom.to_string(key)))
    tokens = Map.get(usage, :tokens, Map.get(usage, "tokens", %{}))

    case direct || Map.get(tokens, key, Map.get(tokens, Atom.to_string(key))) do
      value when is_number(value) -> value
      _other -> 0
    end
  end

  defp usage_value(_usage, _key), do: 0

  defp model_tag_values(metadata) do
    Map.update(metadata, :model, nil, &model_name/1)
  end

  defp model_name(%{id: id}) when is_binary(id), do: id
  defp model_name(model) when is_binary(model), do: model
  defp model_name(_model), do: "unknown"

  defp semantic_log_mode do
    case config_value(telemetry_config(), :semantic_log_mode) do
      mode when mode in @log_modes -> mode
      _other -> :off
    end
  end

  defp semantic_slow_threshold_ms do
    case config_value(telemetry_config(), :semantic_slow_threshold_ms) do
      value when is_integer(value) and value >= 0 -> value
      _other -> 1_000
    end
  end

  defp log_semantic?(:off, _event, _measurements, _metadata), do: false
  defp log_semantic?(:all, _event, _measurements, _metadata), do: true

  defp log_semantic?(:errors, event, _measurements, metadata),
    do: semantic_error?(event, metadata)

  defp log_semantic?(:interesting, event, measurements, metadata),
    do:
      semantic_error?(event, metadata) or interesting_outcome?(event, metadata) or
        slow_semantic?(measurements)

  defp semantic_error?([:jido, :ai, :limit, :exceeded], _metadata), do: true

  defp semantic_error?([:jido, :ai, :agent, :stop], %{status: :blocked, reason_code: code})
       when code in [:limits, :output],
       do: true

  defp semantic_error?(event, metadata) do
    List.last(event) == :exception or metadata[:status] in [:error, :failed] or
      metadata[:outcome] == :error or error_http_status?(metadata[:http_status])
  end

  defp error_http_status?(status) when is_integer(status), do: status >= 400
  defp error_http_status?(_status), do: false

  defp interesting_outcome?([:jido, :ai, :agent, ending], metadata)
       when ending in [:stop, :exception],
       do: metadata[:status] not in [nil, :completed]

  defp interesting_outcome?(_event, _metadata), do: false

  defp slow_semantic?(measurements) do
    case measurements[:duration] do
      duration when is_integer(duration) and duration >= 0 ->
        System.convert_time_unit(duration, :native, :microsecond) / 1_000 >=
          semantic_slow_threshold_ms()

      _other ->
        false
    end
  end

  defp log_fields([:req_llm | _rest], measurements, metadata) do
    usage = metadata[:usage] || %{}

    metadata
    |> Map.take([
      :request_id,
      :conversation_id,
      :provider,
      :model,
      :operation,
      :mode,
      :transport,
      :http_status,
      :finish_reason,
      :error_type
    ])
    |> Map.put(:conversation_id, req_llm_conversation_id(metadata))
    |> Map.update(:model, nil, &model_name/1)
    |> Map.merge(Map.take(measurements, [:duration, :system_time]))
    |> Map.merge(%{
      input_tokens: usage_value(usage, :input_tokens),
      output_tokens: usage_value(usage, :output_tokens),
      cache_read_tokens: usage_value(usage, :cache_read_tokens),
      cache_write_tokens: usage_value(usage, :cache_write_tokens),
      reasoning_tokens: usage_value(usage, :reasoning_tokens),
      total_cost: usage_value(usage, :total_cost)
    })
    |> compact()
  end

  defp log_fields(_event, measurements, metadata) do
    metadata
    |> Map.take([
      :agent_id,
      :agent_definition_id,
      :agent_version,
      :agent_module,
      :agent_name,
      :reasoning,
      :reasoning_method,
      :request_id,
      :req_llm_request_id,
      :run_id,
      :session_id,
      :thread_id,
      :turn_id,
      :tool_call_id,
      :tool_name,
      :status,
      :reason_code,
      :reason,
      :limit,
      :model,
      :error_type,
      :error_code,
      :retryable?
    ])
    |> Map.merge(
      Map.take(measurements, [
        :duration,
        :value,
        :maximum,
        :model_calls,
        :tool_rounds,
        :tool_calls,
        :tool_errors,
        :retries,
        :reasoning_steps,
        :input_tokens,
        :output_tokens,
        :cache_read_tokens,
        :cache_write_tokens,
        :reasoning_tokens,
        :total_cost
      ])
    )
    |> compact()
  end

  defp req_llm_conversation_id(metadata) do
    metadata[:conversation_id] ||
      metadata
      |> Map.get(:request_options, %{})
      |> map_value(:conversation_id)
  end

  defp map_value(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, to_string(key)))
  defp map_value(_map, _key), do: nil

  defp format_fields(fields) do
    fields
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map_join(" ", fn {key, value} -> "#{key}=#{format_value(value)}" end)
  end

  defp format_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_value(value) when is_binary(value), do: value |> escape() |> truncate(128)
  defp format_value(value) when is_number(value) or is_boolean(value), do: to_string(value)
  defp format_value(value), do: inspect(value, limit: 4, printable_limit: 128)

  defp escape(value) do
    for <<codepoint::utf8 <- value>>, into: "" do
      case codepoint do
        ?\\ ->
          "\\\\"

        ?\r ->
          "\\r"

        ?\n ->
          "\\n"

        ?\t ->
          "\\t"

        codepoint when codepoint < 32 or codepoint in 127..159 ->
          "\\u{" <> Integer.to_string(codepoint, 16) <> "}"

        codepoint ->
          <<codepoint::utf8>>
      end
    end
  end

  defp truncate(value, max) when byte_size(value) <= max, do: value

  defp truncate(value, max) do
    value
    |> String.codepoints()
    |> Enum.reduce_while({[], 0}, fn codepoint, {acc, size} ->
      next = size + byte_size(codepoint)

      if next <= max - 3,
        do: {:cont, {[codepoint | acc], next}},
        else: {:halt, {acc, size}}
    end)
    |> elem(0)
    |> Enum.reverse()
    |> IO.iodata_to_binary()
    |> Kernel.<>("...")
  end

  defp compact(values) do
    values
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp attach_once(id, events, handler) do
    case :telemetry.attach_many(id, events, handler, nil) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  defp configured_open_telemetry_options do
    config_value(Application.get_env(:jido, :ai_opentelemetry, []), :options) || []
  end

  defp telemetry_config, do: Application.get_env(:jido, :ai_telemetry, [])
  defp config_value(config, key) when is_list(config), do: Keyword.get(config, key)
  defp config_value(config, key) when is_map(config), do: Map.get(config, key)
  defp config_value(_config, _key), do: nil
end
