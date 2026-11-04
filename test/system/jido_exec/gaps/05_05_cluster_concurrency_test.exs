defmodule Jido.Exec.System.Gaps.ClusterConcurrencyProbe do
  use ExUnit.Case, async: true
  @moduletag :system
  @moduletag :skip

  test "enforces one concurrency budget across cluster owners" do
    flunk("expected cluster-wide admission and concurrency controls")
  end
end
