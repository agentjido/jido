defmodule Jido.Exec.System.Gaps.WorkerLossProbe do
  use ExUnit.Case, async: true
  @moduletag :system
  @moduletag :skip

  test "monitors remote worker loss and redelivers uncertain work" do
    flunk("expected remote worker monitoring and redelivery")
  end
end
