Code.require_file("credential_boundaries.ex", __DIR__)

defmodule Jido.Examples.Operations.CredentialPreflightTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.Examples.Operations.CredentialPreflight

  test "a fake credential stays in execution context and out of the result" do
    secret = "fake-secret-value"
    context = %{runtime_environment: %{"EXAMPLE_AI_TOKEN" => secret}}

    assert {:ok, result} =
             Jido.Exec.run(CredentialPreflight, %{provider: :example_ai, tenant: "tenant-7"}, context)

    assert result == %{provider: "example_ai", tenant: "tenant-7", ready: true, reason: nil}
    refute inspect(result) =~ secret
  end

  test "missing and invalid credentials return the same safe status" do
    for environment <- [%{}, %{"EXAMPLE_AI_TOKEN" => "short"}] do
      assert {:ok, %{ready: false, reason: "credential is missing or invalid"}} =
               Jido.Exec.run(
                 CredentialPreflight,
                 %{provider: :example_ai, tenant: "tenant-7"},
                 %{runtime_environment: environment}
               )
    end
  end
end
