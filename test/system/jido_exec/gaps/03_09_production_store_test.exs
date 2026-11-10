defmodule Jido.Exec.System.Gaps.ProductionStoreProbe do
  use ExUnit.Case, async: true
  @moduletag :system
  @moduletag :skip

  test "discovers and fences incomplete executions in a production Store" do
    flunk("expected a production Runner Store with discovery, leases, and fencing")
  end
end
