defmodule Jido.AI.ToolResult do
  @moduledoc "Separates a local Action result from bounded model-visible content."

  @default_max_bytes 16_384

  @doc false
  @spec portable_outcome(map()) :: map()
  def portable_outcome(%{status: :ok, value: %ReqLLM.ToolResult{} = result} = outcome),
    do: %{outcome | value: portable_content_result(result)}

  def portable_outcome(%{status: :error, error: %ReqLLM.ToolResult{} = result} = outcome),
    do: %{outcome | error: portable_content_result(result)}

  def portable_outcome(outcome), do: outcome

  @doc "Normalizes one local Action outcome without putting its value in model context."
  @spec normalize(map(), pos_integer()) :: map()
  def normalize(outcome, max_bytes \\ @default_max_bytes)

  def normalize(%{status: :ok, value: %ReqLLM.ToolResult{} = result}, max_bytes)
      when is_integer(max_bytes) and max_bytes > 0 do
    normalize_content_result(result, :ok, max_bytes)
  end

  def normalize(
        %{status: :ok, value: %{__jido_ai_tool_result__: 1} = result},
        max_bytes
      )
      when is_integer(max_bytes) and max_bytes > 0 do
    normalize_content_result(result, :ok, max_bytes)
  end

  def normalize(
        %{status: :ok, value: %{"__jido_ai_tool_result__" => 1} = result},
        max_bytes
      )
      when is_integer(max_bytes) and max_bytes > 0 do
    normalize_content_result(result, :ok, max_bytes)
  end

  def normalize(%{status: :ok, value: value}, max_bytes)
      when is_integer(max_bytes) and max_bytes > 0 do
    {model_content, metadata} = project(value, max_bytes)

    %{
      status: :ok,
      value: value,
      model_content: model_content,
      content_parts: nil,
      result_metadata: %{},
      error: nil,
      metadata: metadata
    }
  end

  def normalize(%{status: :error, error: %ReqLLM.ToolResult{} = result}, max_bytes)
      when is_integer(max_bytes) and max_bytes > 0 do
    normalize_content_result(result, :error, max_bytes)
  end

  def normalize(
        %{status: :error, error: %{__jido_ai_tool_result__: 1} = result},
        max_bytes
      )
      when is_integer(max_bytes) and max_bytes > 0 do
    normalize_content_result(result, :error, max_bytes)
  end

  def normalize(
        %{status: :error, error: %{"__jido_ai_tool_result__" => 1} = result},
        max_bytes
      )
      when is_integer(max_bytes) and max_bytes > 0 do
    normalize_content_result(result, :error, max_bytes)
  end

  def normalize(%{status: :error, error: error}, max_bytes)
      when is_integer(max_bytes) and max_bytes > 0 do
    safe_error = %{
      "status" => "error",
      "error" => %{
        "type" => safe_type(field(error, :type)),
        "message" => safe_message(field(error, :message)),
        "retryable" => field(error, :retryable?) == true
      }
    }

    {model_content, metadata} = project(safe_error, max_bytes)

    %{
      status: :error,
      value: nil,
      model_content: model_content,
      content_parts: nil,
      result_metadata: %{},
      error: safe_error["error"],
      metadata: metadata
    }
  end

  def normalize(_outcome, max_bytes) when is_integer(max_bytes) and max_bytes > 0 do
    normalize(
      %{
        status: :error,
        error: %{type: :invalid_tool_result, message: "tool action returned an invalid result"}
      },
      max_bytes
    )
  end

  @doc "Returns JSON-safe model content and size metadata."
  @spec project(term(), pos_integer()) :: {term(), map()}
  def project(value, max_bytes \\ @default_max_bytes)

  def project(value, max_bytes) when is_integer(max_bytes) and max_bytes > 0 do
    case Jason.encode(value) do
      {:ok, encoded} when byte_size(encoded) <= max_bytes ->
        {Jason.decode!(encoded), %{bytes: byte_size(encoded), max_bytes: max_bytes, truncated: false}}

      {:ok, encoded} ->
        content = %{
          "status" => "truncated",
          "message" => "tool result exceeded the model-content limit",
          "original_bytes" => byte_size(encoded),
          "max_bytes" => max_bytes
        }

        {content, %{bytes: byte_size(encoded), max_bytes: max_bytes, truncated: true}}

      {:error, _reason} ->
        content = %{
          "status" => "error",
          "error" => %{
            "type" => "invalid_tool_result",
            "message" => "tool result is not JSON-compatible",
            "retryable" => false
          }
        }

        {content, %{bytes: nil, max_bytes: max_bytes, truncated: false}}
    end
  end

  defp normalize_content_result(result, status, max_bytes) do
    case project_content_result(result, max_bytes) do
      {:ok, content_parts, model_content, result_metadata, metadata} ->
        %{
          status: status,
          value: field(result, :output),
          model_content: model_content,
          content_parts: content_parts,
          result_metadata: result_metadata,
          error: content_result_error(status, field(result, :output)),
          metadata: metadata
        }

      {:truncated, model_content, metadata} ->
        %{
          status: status,
          value: field(result, :output),
          model_content: model_content,
          content_parts: nil,
          result_metadata: %{},
          error: content_result_error(status, field(result, :output)),
          metadata: metadata
        }

      {:error, reason} ->
        normalize(
          %{
            status: :error,
            error: %{type: :invalid_tool_result, message: reason, retryable?: false}
          },
          max_bytes
        )
    end
  end

  defp project_content_result(result, max_bytes) do
    content = field(result, :content) || []
    output = field(result, :output)
    result_metadata = field(result, :metadata) || %{}

    with :ok <- validate_content_parts(content),
         {:ok, encoded} <-
           Jason.encode(%{
             content: content,
             output: output,
             metadata: result_metadata
           }) do
      bytes = byte_size(encoded)

      if bytes <= max_bytes do
        decoded = Jason.decode!(encoded)

        {:ok, decoded["content"] || [], decoded["output"], decoded["metadata"] || %{},
         %{
           bytes: bytes,
           max_bytes: max_bytes,
           truncated: false,
           content_parts: length(content)
         }}
      else
        content = %{
          "status" => "truncated",
          "message" => "tool result exceeded the model-content limit",
          "original_bytes" => bytes,
          "max_bytes" => max_bytes
        }

        {:truncated, content, %{bytes: bytes, max_bytes: max_bytes, truncated: true, content_parts: 0}}
      end
    else
      {:error, _reason} -> {:error, "tool result content parts are invalid"}
    end
  end

  defp validate_content_parts(parts) when is_list(parts) do
    if List.improper?(parts) do
      {:error, :invalid_content_parts}
    else
      Enum.reduce_while(parts, :ok, fn part, :ok ->
        case ReqLLM.Context.normalize(%{role: :user, content: [part]}) do
          {:ok, %ReqLLM.Context{messages: [%ReqLLM.Message{content: [_one]}]}} ->
            {:cont, :ok}

          _other ->
            {:halt, {:error, :invalid_content_part}}
        end
      end)
    end
  end

  defp validate_content_parts(_parts), do: {:error, :invalid_content_parts}

  defp content_result_error(:ok, _output), do: nil

  defp content_result_error(:error, output) do
    %{
      "type" => safe_type(field(output, :type)),
      "message" => safe_message(field(output, :message)),
      "retryable" => field(output, :retryable?) == true
    }
  end

  defp safe_type(value) when is_atom(value) and value not in [nil, true, false], do: Atom.to_string(value)
  defp safe_type(value) when is_binary(value) and value != "", do: truncate(value, 128)
  defp safe_type(_value), do: "tool_error"

  defp safe_message(value) when is_binary(value) and value != "", do: truncate(value, 1_024)
  defp safe_message(_value), do: "tool action failed"

  defp truncate(value, max_bytes) when byte_size(value) <= max_bytes, do: value

  defp truncate(value, max_bytes) do
    value
    |> String.codepoints()
    |> Enum.reduce_while("", fn codepoint, output ->
      if byte_size(output) + byte_size(codepoint) > max_bytes,
        do: {:halt, output},
        else: {:cont, output <> codepoint}
    end)
  end

  defp portable_content_result(result) do
    case Jason.encode(%{
           content: field(result, :content) || [],
           output: field(result, :output),
           metadata: field(result, :metadata) || %{}
         }) do
      {:ok, encoded} ->
        decoded = Jason.decode!(encoded)

        %{
          __jido_ai_tool_result__: 1,
          content: decoded["content"] || [],
          output: decoded["output"],
          metadata: decoded["metadata"] || %{}
        }

      {:error, _reason} ->
        %{
          __jido_ai_tool_result__: 1,
          content: :invalid,
          output: nil,
          metadata: %{}
        }
    end
  end

  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp field(_value, _key), do: nil
end
