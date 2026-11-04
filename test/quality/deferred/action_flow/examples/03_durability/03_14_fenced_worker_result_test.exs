defmodule JidoTest.Quality.Deferred.ActionFlow.FencedWorkerResultProbe do
  use ExUnit.Case, async: true
  @moduletag :skip

  test "rejects one worker result with a stale fence" do
    flunk("expected public worker lease renewal and fenced result acceptance")
  end
end
