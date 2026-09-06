defmodule Jido.Examples.Factory.Error do
  @moduledoc "Safe model error details for Agent replies and the chat prompt."

  @doc "Converts a provider failure to an Action error without request bodies or keys."
  def request(reason, model_spec, opts) do
    reason = unwrap(reason)
    {model, key_env, key, key_source} = request_info(model_spec, opts)
    status = status(reason)
    label = if status, do: "HTTP #{status}", else: "request error"

    message =
      "Model #{model} (#{label}): #{provider_message(reason)}" <>
        key_hint(status, key_env, key_source)

    Jido.Action.Error.execution_error(redact(message, key), %{
      reason: :model_request_failed,
      model: model,
      status: status,
      key_env: key_env,
      key_source: key_source
    })
  end

  defp unwrap(%ReqLLM.Error.API.Stream{cause: cause}) when not is_nil(cause), do: unwrap(cause)
  defp unwrap({:error, reason}), do: unwrap(reason)
  defp unwrap(reason), do: reason

  @doc "Returns a short message for terminal output and result Signals."
  def message(%{message: message}) when is_binary(message), do: message
  def message(reason) when is_atom(reason), do: Atom.to_string(reason)
  def message(_reason), do: "Request failed."

  defp request_info(model_spec, opts) do
    case ReqLLM.model(model_spec) do
      {:ok, model} ->
        {key, source} =
          case ReqLLM.Keys.get(model, opts) do
            {:ok, key, source} -> {key, source}
            {:error, _} -> {nil, :missing}
          end

        {"#{model.provider}:#{model.id}", ReqLLM.Keys.env_var_name(model.provider), key, source}

      {:error, _} ->
        {"FACTORY_MODEL", nil, nil, :missing}
    end
  end

  defp status(%{status: status}) when is_integer(status) and status in 100..599, do: status
  defp status(_reason), do: nil

  # Read only known diagnostic fields. Never inspect the whole ReqLLM exception:
  # it can contain authorization headers, request options, or message bodies.
  defp provider_message(%ReqLLM.Error.API.Request{reason: reason}) when is_binary(reason),
    do: reason

  defp provider_message(%ReqLLM.Error.API.Response{reason: reason}) when is_binary(reason),
    do: reason

  defp provider_message(%ReqLLM.Error.Invalid.Parameter{parameter: parameter})
       when is_binary(parameter),
       do: "Invalid parameter: #{parameter}"

  defp provider_message(%ReqLLM.Error.Validation.Error{reason: reason}) when is_binary(reason),
    do: reason

  defp provider_message(_reason), do: "Check the model settings and provider connection."

  defp key_hint(401, key_env, :system),
    do: " Check #{key_env} in .env or your shell. Shell values take precedence."

  defp key_hint(401, _key_env, :option), do: " Check llm_opts[:api_key]."

  defp key_hint(401, _key_env, :application),
    do: " Check the API key in the :req_llm application configuration."

  defp key_hint(_status, _key_env, _source), do: ""

  defp redact(message, key) do
    message =
      if is_binary(key) and key != "",
        do: String.replace(message, key, "[REDACTED]"),
        else: message

    message |> String.replace(~r/[\x00-\x1F\x7F]/u, " ") |> String.slice(0, 1_500)
  end
end
