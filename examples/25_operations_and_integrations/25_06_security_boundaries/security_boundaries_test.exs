Code.require_file("security_boundaries.ex", __DIR__)

defmodule Jido.Examples.Operations.SecurityBoundariesTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.Examples.Operations.SecureOperationFlow

  test "an authenticated operator can run one allowlisted operation" do
    context = %{principal: %{tenant: "tenant-7", roles: [:operator]}}

    assert {:ok, %{status: "simulated", operation: "restart_service"}} =
             Jido.Exec.run(
               SecureOperationFlow,
               %{tenant: "tenant-7", operation: :restart_service},
               context
             )
  end

  test "missing identity, wrong tenant, and insufficient role stop before execution" do
    input = %{tenant: "tenant-7", operation: :restart_service}

    assert {:error, _reason} = Jido.Exec.run(SecureOperationFlow, input, %{})

    assert {:error, _reason} =
             Jido.Exec.run(SecureOperationFlow, input, %{
               principal: %{tenant: "tenant-8", roles: [:operator]}
             })

    assert {:error, _reason} =
             Jido.Exec.run(SecureOperationFlow, input, %{
               principal: %{tenant: "tenant-7", roles: [:reader]}
             })
  end

  test "unknown operations fail schema validation" do
    assert {:error, _reason} =
             Jido.Exec.run(
               SecureOperationFlow,
               %{tenant: "tenant-7", operation: :shell},
               %{principal: %{tenant: "tenant-7", roles: [:operator]}}
             )
  end
end
