Code.require_file("signal_schema_and_context.ex", __DIR__)

defmodule Jido.Examples.Signals.SignalSchemaAndContextTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.Signals.SignalSchemaAndContext.TenantRequest
  alias Jido.Signal.Context

  test "keeps domain data separate from transport context" do
    signal = TenantRequest.new_for_tenant!(%{request_id: "request-1", operation: :read}, "tenant-7")

    assert signal.data == %{request_id: "request-1", operation: :read}
    assert Context.get(signal, "tenantid") == "tenant-7"
    assert Context.names(signal) == ["tenantid"]
  end

  test "rejects invalid domain data and invalid context names" do
    assert {:error, _errors} = TenantRequest.new(%{request_id: "", operation: :delete})
    signal = TenantRequest.new!(%{request_id: "request-1", operation: :write})
    assert {:error, _message} = Context.put(signal, "name-is-not-valid", "value")
  end
end
