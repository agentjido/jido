defmodule JidoTest.Quality.Deferred.ActionFlow.LeaseAndFencingProbe do
  use ExUnit.Case, async: true
  @moduletag :skip

  test "rejects one Store change from a stale execution owner" do
    flunk("expected cluster-wide execution-owner leases and fencing")
  end
end
