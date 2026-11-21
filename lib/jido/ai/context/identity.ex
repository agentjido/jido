defmodule Jido.AI.Context.Identity do
  @moduledoc false

  alias ReqLLM.Message

  @doc false
  @spec request(map()) :: map()
  def request(request) do
    %{
      model: portable(request.model),
      context: req_llm(request.context),
      options: options(request.options)
    }
  end

  @doc false
  @spec req_llm(ReqLLM.Context.t()) :: map()
  def req_llm(%ReqLLM.Context{} = context) do
    %{
      messages: Enum.map(context.messages, &message/1),
      tools: Enum.map(context.tools, &tool/1)
    }
  end

  @doc false
  @spec term_digest(term()) :: String.t()
  def term_digest(value) do
    value
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc false
  @spec portable(term()) :: term()
  def portable(nil), do: nil
  def portable(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  def portable(value) when is_atom(value), do: value
  def portable(value) when is_function(value), do: "[FUNCTION]"
  def portable(value) when is_pid(value), do: "[PID]"
  def portable(value) when is_reference(value), do: "[REFERENCE]"
  def portable(value) when is_port(value), do: "[PORT]"
  def portable(value) when is_tuple(value), do: value |> Tuple.to_list() |> Enum.map(&portable/1)
  def portable(value) when is_list(value), do: Enum.map(value, &portable/1)
  def portable(%_module{} = value), do: value |> Map.from_struct() |> portable()

  def portable(value) when is_map(value) do
    Map.new(value, fn {key, item} ->
      portable_key = if is_atom(key) or is_binary(key), do: key, else: inspect(key)

      if sensitive_key?(portable_key) do
        {portable_key, "[REDACTED]"}
      else
        {portable_key, portable(item)}
      end
    end)
  end

  def portable(value), do: inspect(value)

  defp options(options) do
    options
    |> Map.new()
    |> Map.update(:tools, nil, fn tools -> Enum.map(tools || [], &tool/1) end)
    |> Map.update(:output, nil, &portable/1)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
    |> portable()
  end

  defp message(%Message{} = message) do
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

  defp tool(%ReqLLM.Tool{} = tool) do
    schema = ReqLLM.Tool.to_json_schema(tool)

    %{
      name: tool.name,
      description: tool.description,
      strict: tool.strict,
      provider_options: portable(tool.provider_options),
      schema_digest: term_digest(schema),
      schema: portable(schema)
    }
  rescue
    _error -> %{name: tool.name, description: tool.description, strict: tool.strict}
  end

  defp tool(tool), do: portable(tool)

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
end
