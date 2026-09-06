defmodule Jido.Examples.Handoff.Worker do
  @moduledoc "A specialist that acknowledges an offer and returns its saved ownership generation."
  use Jido.Agent, name: "research_handoff_worker"

  agent do
    schema Zoi.object(%{
             request: Zoi.string() |> Zoi.default(""),
             owner: Zoi.string() |> Zoi.default(""),
             generation: Zoi.integer() |> Zoi.default(0)
           })
  end

  routes do
    signal_source "/examples/handoff-worker"

    route "worker.prepare" do
      action input,
        name: "research_handoff_prepare",
        schema:
          Zoi.object(%{request: Zoi.string(), owner: Zoi.string(), generation: Zoi.integer()}),
        context: _context do
        {:ok, input}
      end
    end

    route "worker.ack" do
      action _input, name: "research_handoff_ack", schema: Zoi.object(%{}), context: context do
        {:ok, context.agent_state,
         [
           Jido.Agent.Directive.emit_to_parent(
             Jido.Examples.Handoff.signal("handoff.ack", context.agent_state)
           )
         ]}
      end

      define :acknowledge
    end

    route "worker.complete" do
      action %{result: result},
        name: "research_handoff_complete",
        schema: Zoi.object(%{result: Zoi.string()}),
        context: context do
        data = Map.put(context.agent_state, :result, result)

        {:ok, context.agent_state,
         [
           Jido.Agent.Directive.emit_to_parent(
             Jido.Examples.Handoff.signal("handoff.result", data)
           )
         ]}
      end

      define :complete, args: [:result]
    end
  end
end

defmodule Jido.Examples.Handoff.Change do
  @moduledoc false
  use Jido.Action, name: "research_handoff_change"
  alias Jido.Agent.Directive
  alias Jido.Examples.Handoff

  def run(input, %{agent_state: state, signal: signal}) do
    change(signal.type, input, state)
  end

  defp change("handoff.boot", _, %{alive: []} = state) do
    {:ok, state,
     Enum.map(state.desired, &spawn_worker/1) ++
       [offer(state.request, state.owner, state.generation)]}
  end

  defp change("handoff.transfer", %{owner: owner}, %{pending: nil, result: nil} = state) do
    generation = state.next_generation
    pending = %{owner: owner, generation: generation}

    {:ok, %{state | pending: pending, next_generation: generation + 1},
     [offer(state.request, owner, generation)]}
  end

  defp change(
         "handoff.ack",
         %{request: request, owner: owner, generation: generation},
         %{request: request, pending: %{owner: owner, generation: generation}, result: nil} =
           state
       ) do
    {:ok, %{state | owner: owner, generation: generation, pending: nil}}
  end

  defp change(
         "handoff.result",
         %{request: request, owner: owner, generation: generation, result: result},
         %{request: request, owner: owner, generation: generation, result: nil} = state
       ) do
    {:ok, %{state | result: result, pending: nil}}
  end

  defp change("handoff.abort", _, state), do: {:ok, %{state | pending: nil}}

  defp change("handoff.reconcile", _, state) do
    {:ok, state, Enum.map(state.desired -- state.alive, &spawn_worker/1)}
  end

  defp change("jido.agent.child.started", %{tag: tag}, state) do
    {:ok, %{state | alive: Enum.uniq([tag | state.alive])}}
  end

  defp change("jido.agent.child.exit", %{tag: tag}, state) do
    pending = if match?(%{owner: ^tag}, state.pending), do: nil, else: state.pending
    {:ok, %{state | alive: List.delete(state.alive, tag), pending: pending}}
  end

  defp change(_, _, state), do: {:ok, state}
  defp spawn_worker(tag), do: Directive.spawn_agent(Handoff.Worker, tag, restart: :temporary)

  defp offer(request, owner, generation) do
    Directive.emit_to_child(
      owner,
      Handoff.signal("worker.prepare", %{request: request, owner: owner, generation: generation})
    )
  end
end

defmodule Jido.Examples.Handoff do
  @moduledoc """
  Application-owned request transfer with acknowledged generations.
  The coordinator is the authority for accepted results. The previous owner
  remains authoritative until acknowledgement. Reconciliation is an explicit
  command after lifecycle Signals; this example handles one request at a time.
  """
  use Jido.Agent, name: "research_handoff"

  agent do
    schema Zoi.object(%{
             request: Zoi.string() |> Zoi.default("case-1"),
             owner: Zoi.string() |> Zoi.default("general"),
             generation: Zoi.integer() |> Zoi.default(0),
             next_generation: Zoi.integer() |> Zoi.default(1),
             pending: Zoi.map() |> Zoi.nullable() |> Zoi.default(nil),
             result: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil),
             desired: Zoi.list(Zoi.string()) |> Zoi.default(["general", "billing"]),
             alive: Zoi.list(Zoi.string()) |> Zoi.default([])
           })
  end

  routes do
    route "handoff.*", Jido.Examples.Handoff.Change
    route "jido.agent.child.*", Jido.Examples.Handoff.Change
  end

  def signal(type, data \\ %{}), do: Jido.Signal.new!(type, data, source: "/examples/handoff")

  def command(server, type, data \\ %{}),
    do: Jido.AgentServer.call(server, signal("handoff." <> type, data))
end
