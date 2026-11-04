defmodule Jido.Exec.System.Gaps.AutomaticRecoveryProbe do
  use ExUnit.Case, async: true
  @moduletag :system
  @moduletag :skip

  test "discovers and resumes incomplete executions during startup" do
    flunk("expected automatic incomplete-execution discovery and recovery")
  end
end
