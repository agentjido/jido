defmodule JidoTest.Quality.Deferred.ActionFlow.WorkerClaimProbe do
  use ExUnit.Case, async: true
  @moduletag :skip

  test "claims one pending dispatch atomically for one worker" do
    flunk("expected a public durable worker-claim contract")
  end
end
