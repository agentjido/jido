defmodule Jido.Topology.Codec.ValueTest do
  use JidoTest.Case, async: true
  alias Jido.Agent.Codec.Registry
  alias Jido.Topology.Codec.Value
  alias Jido.Topology.{Ref, Reference}

  test "tuples, struct values and references round trip through JSON" do
    day = ~D[2026-09-05]
    registry = Registry.new!(%{"key" => {:atom, :initial}, "date" => {:value, day}})
    value = {Reference.input(:initial), Ref.ref(:subsystem, :worker), day}
    assert {:ok, encoded} = Value.encode(value, registry)
    assert {:ok, ^value} = Value.decode(Jason.decode!(Jason.encode!(encoded)), registry)
    assert Value.entries(value) == [{:atom, :initial}, {:value, day}]
  end

  test "malformed maps and duplicate decoded keys return errors" do
    registry = Registry.new!(%{})

    for {entries, message} <- [
          {[["key"]], "Invalid topology map entry"},
          {[["key", 1], ["key", 2]], "Duplicate decoded map key"}
        ] do
      assert {:error, error} = Value.decode(%{"$type" => "map", "entries" => entries}, registry)
      assert error.message == message
    end
  end
end
