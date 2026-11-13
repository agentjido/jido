Code.require_file("pure_counter.ex", __DIR__)

defmodule Jido.Examples.PureCounterTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.PureCounter

  test "cmd returns a new candidate and leaves the source unchanged" do
    source = PureCounter.instantiate!(id: "pure-counter", state: %{count: 2})
    signal = PureCounter.add_signal!(%{amount: 3})

    assert {:ok, candidate, []} = PureCounter.cmd(source, signal)
    assert source.state == %{count: 2}
    assert candidate.state == %{count: 5}
    assert candidate.id == source.id
  end

  test "failed validation returns no candidate state" do
    source = PureCounter.instantiate!(id: "pure-counter", state: %{count: 2})
    signal = PureCounter.add_signal!(%{amount: "three"})

    assert {:error, %Jido.Error.ValidationError{}} = PureCounter.cmd(source, signal)
    assert source.state == %{count: 2}
  end
end
