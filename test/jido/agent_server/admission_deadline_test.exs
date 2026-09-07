defmodule Jido.AgentServer.AdmissionDeadlineTest do
  use ExUnit.Case, async: true

  alias Jido.AgentServer.AdmissionDeadline

  test "creates deadlines in the caller clock domain" do
    assert AdmissionDeadline.new(:infinity) == :infinity
    assert AdmissionDeadline.new(25, :caller, fn -> 100 end) == {:caller, 125}
  end

  test "checks a local deadline without a remote clock query" do
    remote_now = fn _origin -> flunk("unexpected remote clock query") end

    refute AdmissionDeadline.expired?({:owner, 101}, :owner, fn -> 100 end, remote_now)
    assert AdmissionDeadline.expired?({:owner, 100}, :owner, fn -> 100 end, remote_now)
  end

  test "checks a remote deadline in its origin clock domain and counts query work" do
    refute remote_expired?({:caller, 2_008}, [1_000, 1_007], 2_000)
    assert remote_expired?({:caller, 2_007}, [1_000, 1_007], 2_000)
  end

  defp remote_expired?(deadline, local_times, origin_time) do
    key = make_ref()
    Process.put(key, local_times)

    try do
      local_now = fn ->
        [now | rest] = Process.get(key)
        Process.put(key, rest)
        now
      end

      origin_now = fn origin ->
        assert origin == :caller
        origin_time
      end

      AdmissionDeadline.expired?(deadline, :owner, local_now, origin_now)
    after
      Process.delete(key)
    end
  end
end
