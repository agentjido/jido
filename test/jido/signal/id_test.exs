defmodule Jido.Signal.IDTest do
  use ExUnit.Case, async: true

  test "keeps the former Signal ID API compatible" do
    {uuid, timestamp} = Jido.Signal.ID.generate()

    assert Jido.Signal.ID.generate!() |> Jido.Signal.ID.valid?()
    assert Jido.Signal.ID.valid?(uuid)
    assert Jido.Signal.ID.extract_timestamp(uuid) == timestamp
    assert Jido.Signal.ID.compare(uuid, String.upcase(uuid)) == :eq
  end
end
