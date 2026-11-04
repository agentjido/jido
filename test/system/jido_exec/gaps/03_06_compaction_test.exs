defmodule Jido.Exec.System.Gaps.CompactionProbe do
  use ExUnit.Case, async: true
  @moduletag :system
  @moduletag :skip

  test "compacts completed activation history atomically" do
    flunk("expected a public Jido Exec activation-history compaction contract")
  end
end
