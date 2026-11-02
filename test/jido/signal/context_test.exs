defmodule Jido.Signal.ContextTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Context

  setup do
    %{signal: Signal.new!("test.event", %{}, source: "/test")}
  end

  test "stores and emits flat scalar attributes", %{signal: signal} do
    assert {:ok, signal} = Signal.put_context(signal, "tenantid", "tenant-123")
    assert {:ok, signal} = Signal.put_context(signal, :attempt, 2)
    assert {:ok, signal} = Signal.put_context(signal, "sampled", true)

    assert Signal.get_context(signal, "tenantid") == "tenant-123"
    assert Enum.sort(Signal.list_context(signal)) == ["attempt", "sampled", "tenantid"]

    wire = Signal.to_map(signal)
    assert wire["tenantid"] == "tenant-123"
    assert wire["attempt"] == 2
    refute Map.has_key?(wire, "extensions")
    refute Map.has_key?(wire, "jido_schema_version")
  end

  test "reads unknown top-level attributes as context", %{signal: signal} do
    wire = Signal.to_map(signal) |> Map.put("tenantid", "tenant-123")

    assert {:ok, decoded} = Signal.from_map(wire)
    assert decoded.extensions == %{"tenantid" => "tenant-123"}
  end

  test "treats extensions as a legal CloudEvents extension name", %{signal: signal} do
    assert {:ok, signal} = Signal.put_context(signal, "extensions", "enabled")
    assert Signal.get_context(signal, "extensions") == "enabled"

    wire = Signal.to_map(signal)
    assert wire["extensions"] == "enabled"
    assert {:ok, decoded} = Signal.from_map(wire)
    assert decoded.extensions == %{"extensions" => "enabled"}
  end

  test "rejects names outside the CloudEvents rules", %{signal: signal} do
    assert {:error, error} = Signal.put_context(signal, "trace_id", "abc")
    assert error =~ "extension name"

    assert {:error, error} = Signal.put_context(signal, "Type", "abc")
    assert error =~ "extension name"

    assert {:error, error} = Signal.put_context(signal, "data", "abc")
    assert error =~ "conflicts"
  end

  test "rejects compound values", %{signal: signal} do
    assert {:error, error} = Signal.put_context(signal, "routing", %{target: "worker"})
    assert error =~ "extension values"
  end

  test "rejects names that collide after normalization" do
    assert {:error, error} =
             Context.normalize(%{"tenantid" => "string", tenantid: "atom"})

    assert error =~ "duplicate extension attribute"
    assert error =~ "tenantid"
  end

  test "deletes a context attribute", %{signal: signal} do
    assert {:ok, signal} = Signal.put_context(signal, "tenantid", "tenant-123")
    signal = Signal.delete_context(signal, "tenantid")
    assert Signal.get_context(signal, "tenantid") == nil
  end
end
