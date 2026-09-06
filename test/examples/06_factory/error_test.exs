defmodule JidoTest.Examples.Factory.ErrorTest do
  use JidoTest.Case, async: false
  @moduletag :example

  alias Jido.Examples.Factory.Error

  test "provider errors use known diagnostic fields and normalize stream failures" do
    for {reason, expected} <- [
          {ReqLLM.Error.API.Response.exception(reason: "service unavailable", status: 503),
           "service unavailable"},
          {ReqLLM.Error.Invalid.Parameter.exception(parameter: "temperature"),
           "Invalid parameter: temperature"},
          {ReqLLM.Error.Validation.Error.exception(reason: "invalid settings"),
           "invalid settings"},
          {:unknown, "Check the model settings and provider connection."}
        ] do
      wrapped = ReqLLM.Error.API.Stream.exception(cause: {:error, reason})
      error = Error.request(wrapped, "anthropic:claude-haiku-4-5", api_key: "fixture-key")
      assert error.message =~ expected
      assert error.details.reason == :model_request_failed
      assert error.details.key_source == :option
    end

    error = Error.request(:unknown, "unknown-provider:unknown-model", [])
    assert error.details.model == "FACTORY_MODEL"
    assert error.details.key_source == :missing
    assert error.details.status == nil
    assert Error.message(:unavailable) == "unavailable"
    assert Error.message({:error, :unknown}) == "Request failed."
  end

  test "authentication hints identify the configured key source without exposing the key" do
    variable = "ANTHROPIC_API_KEY"
    config_key = :anthropic_api_key
    previous_env = System.get_env(variable)
    previous_app = Application.fetch_env(:req_llm, config_key)

    on_exit(fn ->
      if previous_env,
        do: System.put_env(variable, previous_env),
        else: System.delete_env(variable)

      case previous_app do
        {:ok, value} -> Application.put_env(:req_llm, config_key, value)
        :error -> Application.delete_env(:req_llm, config_key)
      end
    end)

    reason = ReqLLM.Error.API.Request.exception(reason: "bad fixture-key\nvalue", status: 401)
    Application.delete_env(:req_llm, config_key)
    System.put_env(variable, "fixture-key")
    error = Error.request(reason, "anthropic:claude-haiku-4-5", [])
    assert error.details.key_source == :system
    assert error.message =~ "Check ANTHROPIC_API_KEY in .env or your shell"
    assert error.message =~ "bad [REDACTED] value"
    refute error.message =~ "fixture-key"

    Application.put_env(:req_llm, config_key, "fixture-key")
    error = Error.request(reason, "anthropic:claude-haiku-4-5", [])
    assert error.details.key_source == :application
    assert error.message =~ ":req_llm application configuration"
    refute error.message =~ "fixture-key"

    Application.delete_env(:req_llm, config_key)
    System.delete_env(variable)
    error = Error.request(:unknown, "anthropic:claude-haiku-4-5", [])
    assert error.details.key_source == :missing
  end
end
