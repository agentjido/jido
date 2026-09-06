defmodule Jido.Examples.DistributedAuthorityProbe do
  @moduledoc """
  DIST-03 probe: one stable Agent identity backed by a shared checkpoint store.

  A replacement Agent can restore the identity and revision on another node.
  Compare-and-swap rejects an older activation after the replacement commits.
  The current runtime has no cluster owner claim, so two nodes can still start
  the same identity before either activation writes. The DIST-03 acceptance
  test retains that failure for design review.
  """
  use Jido.Agent, name: "research_distributed_authority"

  agent do
    schema Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/research/distributed-authority"

    route "distributed.authority.record" do
      action %{value: value},
        name: "research_distributed_authority_record",
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        {:ok, %{context.agent_state | value: value}}
      end

      define :record, args: [:value]
    end
  end
end
