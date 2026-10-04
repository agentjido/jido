defmodule Jido.Examples.OrphanAdoption do
  @moduledoc """
  Shows explicit policy and ownership transfer for surviving child Agents.
  """

  defmodule Child do
    @moduledoc "Records orphan notices and work from its current parent."
    use Jido.Agent, name: "multi_agent_orphan_adoption_child"

    agent do
      schema Zoi.object(%{
               total: Zoi.integer() |> Zoi.default(0),
               orphans: Zoi.list(Zoi.map()) |> Zoi.default([])
             })
    end

    routes do
      route "examples.multi_agent.orphan_adoption.work", __MODULE__.Add
      route "jido.agent.orphaned", __MODULE__.RecordOrphan
    end

    defmodule Add do
      @moduledoc false
      use Jido.Action,
        name: "multi_agent_orphan_adoption_add",
        schema: Zoi.object(%{value: Zoi.integer()})

      def run(%{value: value}, context) do
        {:ok, %{context.agent_state | total: context.agent_state.total + value}}
      end
    end

    defmodule RecordOrphan do
      @moduledoc false
      use Jido.Action,
        name: "multi_agent_orphan_adoption_record_orphan",
        schema:
          Zoi.object(%{
            parent_id: Zoi.string(),
            parent_pid: Zoi.any(),
            tag: Zoi.any(),
            meta: Zoi.map(),
            reason: Zoi.any()
          })

      def run(input, context) do
        event = Map.take(input, [:parent_id, :tag, :meta, :reason])
        {:ok, %{context.agent_state | orphans: context.agent_state.orphans ++ [event]}}
      end
    end
  end

  defmodule Parent do
    @moduledoc "Spawns a policy-bound child and forwards work after adoption."
    use Jido.Agent, name: "multi_agent_orphan_adoption_parent"

    alias Jido.Agent.Directive
    alias Jido.Examples.OrphanAdoption.Child

    agent do
      schema Zoi.object(%{forwarded: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      signal_source "/examples/multi_agent/orphan_adoption"
      route "examples.multi_agent.orphan_adoption.spawn", __MODULE__.Spawn, as: :spawn
      route "examples.multi_agent.orphan_adoption.forward", __MODULE__.Forward, as: :forward
      route "jido.agent.child.*", Jido.Examples.Support.KeepState
    end

    defmodule Spawn do
      @moduledoc false
      use Jido.Action,
        name: "multi_agent_orphan_adoption_spawn",
        schema: Zoi.object(%{policy: Zoi.enum([:continue, :emit_orphan])})

      def run(%{policy: policy}, context) do
        directive =
          Directive.spawn_child(Child, :worker,
            opts: %{on_parent_death: policy},
            meta: %{policy: policy}
          )

        {:ok, context.agent_state, [directive]}
      end
    end

    defmodule Forward do
      @moduledoc false
      use Jido.Action,
        name: "multi_agent_orphan_adoption_forward",
        schema: Zoi.object(%{value: Zoi.integer()})

      def run(%{value: value}, context) do
        signal =
          Jido.Signal.new!(
            "examples.multi_agent.orphan_adoption.work",
            %{value: value},
            source: "/examples/multi_agent/orphan_adoption"
          )

        state = %{context.agent_state | forwarded: context.agent_state.forwarded + 1}
        {:ok, state, [Directive.emit_to_child(:adopted, signal)]}
      end
    end
  end
end
