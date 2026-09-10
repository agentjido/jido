defmodule JidoTest.Examples.Runtime.CausalTraceTest do
  use JidoTest.AgentCase

  @moduletag group: :runtime

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.CausalTrace, as: Example
  alias Jido.Examples.Runtime.EventProbe

  test "parent work, child work, and child results keep one causal trace", %{jido: jido} do
    id = unique_id("example-causal-trace")
    probe = EventProbe.attach([id, id <> "/left", id <> "/right"])

    try do
      assert {:ok, server} = Jido.start_agent(jido, Example, id: id)
      assert {:ok, _} = Example.start_work(server, "request-1", 7)
      eventually(fn -> Server.agent(server).state.results == %{left: 14, right: 14} end)

      turns =
        eventually(fn ->
          turns =
            for %{
                  event: [:jido, :agent, :turn, :settled],
                  metadata: metadata
                } <- EventProbe.events(probe),
                do: metadata

          if length(turns) == 7, do: turns
        end)

      [parent] = Enum.filter(turns, &(&1.signal_type == "examples.runtime.causal_trace.begin"))
      children = Enum.filter(turns, &(&1.signal_type == "examples.runtime.causal_trace.compute"))
      results = Enum.filter(turns, &(&1.signal_type == "examples.runtime.causal_trace.result"))

      assert length(children) == 2
      assert length(results) == 2
      assert Enum.all?(children ++ results, &(&1.trace_id == parent.trace_id))
      assert Enum.all?(children, &(&1.parent_span_id == parent.span_id))

      assert Enum.sort(Enum.map(results, & &1.parent_span_id)) ==
               Enum.sort(Enum.map(children, & &1.span_id))

      refute inspect(turns) =~ "private-causal-agent-state"
    after
      EventProbe.detach(probe)
    end
  end
end
