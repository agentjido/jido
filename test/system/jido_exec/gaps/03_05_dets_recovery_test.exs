defmodule Jido.Exec.System.Gaps.DetsRecoveryProbe do
  use ExUnit.Case, async: true
  @moduletag :system
  @moduletag :skip

  test "restores one managed execution from a DETS-backed Store" do
    flunk("expected a supported DETS Runner Store for Jido Exec")
  end
end
