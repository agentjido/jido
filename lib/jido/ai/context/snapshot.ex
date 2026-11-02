defmodule Jido.AI.Context.Snapshot do
  @moduledoc "A portable inspection record for one Context lifecycle stage."

  alias Jido.AI.Context
  alias ReqLLM.Message

  @schema Zoi.struct(
            __MODULE__,
            %{
              type: Zoi.literal("jido.ai.context.snapshot") |> Zoi.default("jido.ai.context.snapshot"),
              version: Zoi.integer() |> Zoi.default(1),
              context_id: Zoi.string(),
              stage: Zoi.enum([:open, :prepared, :completed]),
              digest: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil),
              request: Zoi.map() |> Zoi.default(%{}),
              response: Zoi.any() |> Zoi.default(nil),
              metadata: Zoi.map() |> Zoi.default(%{}),
              operations: Zoi.map() |> Zoi.default(%{}),
              shape: Zoi.map() |> Zoi.default(%{}),
              content: Zoi.enum([:none, :redacted, :full]) |> Zoi.default(:redacted),
              captured_at_ms: Zoi.integer()
            },
            coerce: true,
            unrecognized_keys: :error
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for a context snapshot."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc false
  @spec new(Context.t(), keyword()) :: t()
  def new(%Context{} = context, opts \\ []) do
    content = Keyword.get(opts, :content, :redacted)
    stage = snapshot_stage(context, Keyword.get(opts, :stage))
    req_llm_context = context.request.context

    %__MODULE__{
      type: "jido.ai.context.snapshot",
      version: 1,
      context_id: context.id,
      stage: stage,
      digest: context.digest,
      request: request_summary(context.request, content),
      response: response_summary(snapshot_result(context, stage), content, context.metadata),
      metadata: portable(context.metadata),
      operations: portable(context.operations),
      shape: context_shape(req_llm_context),
      content: content,
      captured_at_ms: captured_at(context, stage)
    }
  end

  @doc "Converts a snapshot to a portable map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = snapshot), do: snapshot |> Map.from_struct() |> portable()

  @doc "Encodes a snapshot as a portable JSON document."
  @spec encode(t()) :: String.t()
  def encode(%__MODULE__{} = snapshot), do: snapshot |> to_map() |> Jason.encode!()

  @doc "Decodes a portable snapshot JSON document."
  @spec decode(String.t()) :: {:ok, map()} | {:error, term()}
  def decode(document) when is_binary(document) do
    with {:ok, %{"type" => "jido.ai.context.snapshot", "version" => 1} = snapshot} <-
           Jason.decode(document) do
      {:ok, snapshot}
    else
      {:ok, _document} -> {:error, :invalid_context_snapshot}
      error -> error
    end
  end

  def decode(_document), do: {:error, :invalid_context_snapshot}

  @doc "Decodes a portable snapshot JSON document or raises."
  @spec decode!(String.t()) :: map()
  def decode!(document) when is_binary(document) do
    case decode(document) do
      {:ok, snapshot} -> snapshot
      {:error, reason} -> raise ArgumentError, "invalid context snapshot: #{inspect(reason)}"
    end
  end

  @doc "Compares two lifecycle snapshots."
  @spec diff(t(), t()) :: map()
  def diff(%__MODULE__{} = before, %__MODULE__{} = later) do
    before_messages = get_in(before.request, [:context, :messages]) || []
    after_messages = get_in(later.request, [:context, :messages]) || []

    %{
      before: %{stage: before.stage, digest: before.digest},
      after: %{stage: later.stage, digest: later.digest},
      request_changed: before.request != later.request,
      messages_changed: before_messages != after_messages,
      message_count: %{before: length(before_messages), after: length(after_messages)},
      response_changed: before.response != later.response,
      metadata_changed: before.metadata != later.metadata,
      operations_changed: before.operations != later.operations,
      shape_changed: before.shape != later.shape
    }
  end

  @doc false
  @spec request_identity(Context.request()) :: map()
  def request_identity(request) do
    %{
      model: portable(request.model),
      context: req_llm_identity(request.context),
      options: options_summary(request.options, :full)
    }
  end

  @doc false
  @spec req_llm_identity(ReqLLM.Context.t()) :: map()
  def req_llm_identity(%ReqLLM.Context{} = context) do
    %{
      messages: Enum.map(context.messages, &message_identity/1),
      tools: Enum.map(context.tools, &tool_summary(&1, :full))
    }
  end

  defp request_summary(request, content) do
    %{
      model: portable(request.model),
      context: req_llm_summary(request.context, content),
      options: options_summary(request.options, content)
    }
  end

  defp options_summary(options, content) do
    options
    |> Map.new()
    |> Map.update(:tools, nil, fn tools -> Enum.map(tools || [], &tool_summary(&1, content)) end)
    |> Map.update(:output, nil, &output_summary(&1, content))
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
    |> portable()
  end

  defp output_summary(%ReqLLM.Output{} = output, :full), do: portable(output)

  defp output_summary(%ReqLLM.Output{} = output, _content) do
    contract = output.schema || output.element || output.choices

    %{
      type: output.type,
      name: output.name,
      description: output.description,
      contract_digest: Context.term_digest(contract)
    }
  end

  defp output_summary(output, _content), do: portable(output)

  defp req_llm_summary(%ReqLLM.Context{} = context, content) do
    %{
      messages: Enum.map(context.messages, &message_summary(&1, content)),
      tools: Enum.map(context.tools, &tool_summary(&1, content))
    }
  end

  defp message_summary(%Message{} = message, content) do
    base = %{
      role: message.role,
      name: message.name,
      tool_call_id: message.tool_call_id,
      metadata: portable(message.metadata),
      content_digest: Context.term_digest(portable(message.content)),
      content_shape: content_shape(message.content),
      tool_calls: Enum.map(message.tool_calls || [], &tool_call_summary(&1, content)),
      reasoning_details_count: length(message.reasoning_details || [])
    }

    case content do
      :none ->
        base

      :redacted ->
        if message.content == [], do: base, else: Map.put(base, :content, "[REDACTED]")

      :full ->
        base
        |> Map.put(:content, portable(message.content))
        |> Map.put(:reasoning_details, portable(message.reasoning_details))
    end
  end

  defp message_identity(%Message{} = message) do
    %{
      role: message.role,
      content: portable(message.content),
      name: message.name,
      tool_call_id: message.tool_call_id,
      tool_calls: portable(message.tool_calls),
      metadata: portable(message.metadata),
      reasoning_details: portable(message.reasoning_details)
    }
  end

  defp tool_call_summary(call, :full), do: portable(call)

  defp tool_call_summary(call, _content) do
    %{
      id: field(call, :id),
      name: tool_call_name(call),
      arguments_digest: Context.term_digest(tool_call_arguments(call)),
      metadata: portable(ReqLLM.ToolCall.metadata(call))
    }
  end

  defp tool_call_name(%ReqLLM.ToolCall{function: function}), do: field(function, :name)
  defp tool_call_name(call), do: field(call, :name)

  defp tool_call_arguments(%ReqLLM.ToolCall{function: function}), do: field(function, :arguments)
  defp tool_call_arguments(call), do: field(call, :arguments)

  defp tool_summary(%ReqLLM.Tool{} = tool, content) do
    schema = ReqLLM.Tool.to_json_schema(tool)

    summary = %{
      name: tool.name,
      description: tool.description,
      strict: tool.strict,
      provider_options: portable(tool.provider_options),
      schema_digest: Context.term_digest(schema)
    }

    if content == :full, do: Map.put(summary, :schema, portable(schema)), else: summary
  rescue
    _error -> %{name: tool.name, description: tool.description, strict: tool.strict}
  end

  defp tool_summary(tool, :full), do: portable(tool)

  defp tool_summary(tool, _content) do
    %{
      name: field(tool, :name),
      description: field(tool, :description),
      strict: field(tool, :strict) == true,
      schema_digest: Context.term_digest(field(tool, :parameter_schema))
    }
  end

  defp response_summary(nil, _content, _metadata), do: nil

  defp response_summary({:ok, %ReqLLM.Response{} = response}, content, metadata) do
    call_metadata =
      response
      |> ReqLLM.Response.call_metadata()
      |> put_observed_request_id(metadata)
      |> portable()

    summary = %{
      status: :ok,
      call_metadata: call_metadata,
      context: response_context(response, content)
    }

    case {content, response.object} do
      {:full, output} when not is_nil(output) -> Map.put(summary, :output, portable(output))
      {:redacted, output} when not is_nil(output) -> Map.put(summary, :output, "[REDACTED]")
      _other -> summary
    end
  end

  defp response_summary({:error, reason}, :full, metadata) do
    %{status: :error, error: portable(reason), call_metadata: error_call_metadata(metadata)}
  end

  defp response_summary({:error, reason}, _content, metadata) do
    %{status: :error, error: error_summary(reason), call_metadata: error_call_metadata(metadata)}
  end

  defp put_observed_request_id(call_metadata, metadata) do
    case field(call_metadata, :request_id) do
      request_id when is_binary(request_id) and request_id != "" -> call_metadata
      _other -> maybe_put(call_metadata, :request_id, completion_request_id(metadata))
    end
  end

  defp error_call_metadata(metadata) do
    %{}
    |> maybe_put(:request_id, completion_request_id(metadata))
    |> portable()
  end

  defp completion_request_id(metadata) do
    metadata |> field(:completion) |> field(:req_llm_request_id)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp response_context(%ReqLLM.Response{context: %ReqLLM.Context{} = context}, content) do
    req_llm_summary(context, content)
  end

  defp response_context(_response, _content), do: nil

  defp error_summary(reason) when is_exception(reason) do
    %{type: inspect(reason.__struct__), message: Exception.message(reason)}
  end

  defp error_summary(reason), do: %{type: inspect(reason)}

  defp context_shape(%ReqLLM.Context{} = context) do
    %{
      message_count: length(context.messages),
      tool_count: length(context.tools),
      content_part_count: Enum.sum(Enum.map(context.messages, &length(&1.content || []))),
      content_bytes: Enum.sum(Enum.map(context.messages, &content_bytes/1)),
      roles: context.messages |> Enum.map(& &1.role) |> Enum.frequencies(),
      reasoning_message_count: Enum.count(context.messages, fn message -> (message.reasoning_details || []) != [] end)
    }
  end

  defp content_shape(parts) when is_list(parts) do
    %{count: length(parts), types: parts |> Enum.map(&field(&1, :type)) |> Enum.frequencies()}
  end

  defp content_shape(_content), do: %{count: 0, types: %{}}

  defp content_bytes(message) do
    message.content
    |> portable()
    |> Jason.encode!()
    |> byte_size()
  rescue
    _error -> byte_size(:erlang.term_to_binary(message.content))
  end

  defp snapshot_stage(%Context{stage: :completed}, :prepared), do: :prepared
  defp snapshot_stage(%Context{stage: stage}, nil), do: stage
  defp snapshot_stage(%Context{stage: stage}, stage), do: stage

  defp snapshot_stage(_context, stage) do
    raise ArgumentError, "context has no #{inspect(stage)} snapshot"
  end

  defp snapshot_result(%Context{result: result}, :completed), do: result
  defp snapshot_result(_context, _stage), do: nil

  defp captured_at(context, :open), do: context.created_at_ms
  defp captured_at(context, :prepared), do: context.prepared_at_ms || context.created_at_ms

  defp captured_at(context, :completed),
    do: context.completed_at_ms || context.prepared_at_ms || context.created_at_ms

  defp portable(nil), do: nil
  defp portable(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp portable(value) when is_atom(value), do: value
  defp portable(value) when is_function(value), do: "[FUNCTION]"
  defp portable(value) when is_pid(value), do: "[PID]"
  defp portable(value) when is_reference(value), do: "[REFERENCE]"
  defp portable(value) when is_port(value), do: "[PORT]"
  defp portable(value) when is_tuple(value), do: value |> Tuple.to_list() |> Enum.map(&portable/1)
  defp portable(value) when is_list(value), do: Enum.map(value, &portable/1)
  defp portable(%_module{} = value), do: value |> Map.from_struct() |> portable()

  defp portable(value) when is_map(value) do
    Map.new(value, fn {key, item} ->
      portable_key = if is_atom(key) or is_binary(key), do: key, else: inspect(key)

      if sensitive_key?(portable_key) do
        {portable_key, "[REDACTED]"}
      else
        {portable_key, portable(item)}
      end
    end)
  end

  defp portable(value), do: inspect(value)

  defp sensitive_key?(key) do
    key = key |> to_string() |> String.downcase()

    key in [
      "api_key",
      "access_token",
      "auth_token",
      "bearer_token",
      "refresh_token",
      "secret",
      "password",
      "authorization",
      "credential",
      "cookie"
    ] or String.ends_with?(key, ["_api_key", "_secret", "_password", "_credential"])
  end

  defp field(nil, _key), do: nil
  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp field(_value, _key), do: nil
end
