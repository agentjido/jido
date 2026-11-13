Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("support/missing_credentials_client.ex", __DIR__)
Code.require_file("offline_provider_configuration.ex", __DIR__)

defmodule Jido.Examples.Operations.ProviderConfigurationTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.Examples.Operations.{MissingCredentialsClient, ProviderConfiguration}
  alias Jido.Examples.Support.OfflineInferenceClient

  test "runtime context selects an offline provider without changing Agent data" do
    assert {:ok, candidate, [%Jido.Agent.Directive.Reply{signal: reply}]} =
             ProviderConfiguration.ask(OfflineInferenceClient, "Use the offline provider.")

    assert reply.data.status == :completed
    assert reply.data.output == "Offline response"
    refute Map.has_key?(candidate.state, :jido_ai_inference_client)
  end

  test "invalid credentials fail once and do not leak fake credential material" do
    assert {:ok, _candidate, [%Jido.Agent.Directive.Reply{signal: reply}]} =
             ProviderConfiguration.ask(MissingCredentialsClient, "Fail safely.")

    assert reply.data.status == :failed
    assert reply.data.model_calls == 1
    assert reply.data.retries == 0
    refute JSON.encode!(reply.data) =~ "fake-secret-must-not-appear"
  end
end
