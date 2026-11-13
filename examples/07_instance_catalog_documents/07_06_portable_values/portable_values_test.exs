Code.require_file("portable_values.ex", __DIR__)

defmodule Jido.Examples.PortableValuesTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.PortableValues

  test "nested domain data is portable" do
    value = %{
      case_id: "case-42",
      status: :open,
      attempts: 2,
      evidence: [%{kind: :log, bytes: <<1, 2, 3>>}],
      result: {:ok, true}
    }

    assert :ok = PortableValues.validate(value)
    assert PortableValues.portable?(value)
  end

  test "the first process-local value returns its bounded path" do
    value = %{case_id: "case-42", runtime: %{worker: self()}}

    assert {:error, [:agent_state, :runtime, :worker]} = PortableValues.validate(value)
    refute PortableValues.portable?(value)
  end

  test "functions, references, improper lists, and partial bitstrings are rejected" do
    refute PortableValues.portable?(fn -> :ok end)
    refute PortableValues.portable?(make_ref())
    refute PortableValues.portable?([:head | :tail])
    refute PortableValues.portable?(<<1::size(1)>>)
  end
end
