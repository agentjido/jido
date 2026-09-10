defmodule Jido.Examples.Handoff do
  @moduledoc "Coordinates one acknowledged request transfer with explicit generations."
  use Jido.Agent, name: "research_handoff"

  alias Jido.Examples.Handoff.State

  @prefix "examples.research.handoff"

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
    signal_source "/examples/research/handoff"

    route "#{@prefix}.boot" do
      action _input, schema: Zoi.object(%{}), context: context do
        State.boot(context.agent_state)
      end
    end

    route "#{@prefix}.transfer" do
      action input,
        schema: Zoi.object(%{owner: Zoi.string() |> Zoi.min(1)}),
        context: context do
        State.transfer(input, context.agent_state)
      end
    end

    route "#{@prefix}.ack" do
      action input,
        schema:
          Zoi.object(%{
            request: Zoi.string(),
            owner: Zoi.string(),
            generation: Zoi.integer()
          }),
        context: context do
        State.acknowledge(input, context.agent_state)
      end
    end

    route "#{@prefix}.result" do
      action input,
        schema:
          Zoi.object(%{
            request: Zoi.string(),
            owner: Zoi.string(),
            generation: Zoi.integer(),
            result: Zoi.string()
          }),
        context: context do
        State.complete(input, context.agent_state)
      end
    end

    route "#{@prefix}.abort" do
      action _input, schema: Zoi.object(%{}), context: context do
        {:ok, %{context.agent_state | pending: nil}}
      end
    end

    route "#{@prefix}.reconcile" do
      action _input, schema: Zoi.object(%{}), context: context do
        State.reconcile(context.agent_state)
      end
    end

    route "jido.agent.child.started" do
      action %{tag: tag}, schema: Zoi.object(%{tag: Zoi.string()}), context: context do
        {:ok, %{context.agent_state | alive: Enum.uniq([tag | context.agent_state.alive])}}
      end
    end

    route "jido.agent.child.exit" do
      action %{tag: tag}, schema: Zoi.object(%{tag: Zoi.string()}), context: context do
        State.child_exit(tag, context.agent_state)
      end
    end
  end

  def signal(type, data \\ %{}) do
    Jido.Signal.new!(type, data, source: "/examples/research/handoff")
  end

  def command(server, type, data \\ %{}),
    do: Jido.AgentServer.call(server, signal("#{@prefix}.#{type}", data))
end

defmodule Jido.Examples.Handoff.State do
  @moduledoc false

  alias Jido.Agent.Directive
  alias Jido.Examples.Handoff

  def boot(%{alive: []} = state) do
    {:ok, state,
     Enum.map(state.desired, &spawn_worker/1) ++
       [offer(state.request, state.owner, state.generation)]}
  end

  def boot(state), do: {:ok, state}

  def transfer(%{owner: owner}, %{pending: nil, result: nil} = state) do
    generation = state.next_generation
    pending = %{owner: owner, generation: generation}

    {:ok, %{state | pending: pending, next_generation: generation + 1},
     [offer(state.request, owner, generation)]}
  end

  def transfer(_input, state), do: {:ok, state}

  def acknowledge(
        %{request: request, owner: owner, generation: generation},
        %{request: request, pending: %{owner: owner, generation: generation}, result: nil} = state
      ) do
    {:ok, %{state | owner: owner, generation: generation, pending: nil}}
  end

  def acknowledge(_input, state), do: {:ok, state}

  def complete(
        %{request: request, owner: owner, generation: generation, result: result},
        %{request: request, owner: owner, generation: generation, result: nil} = state
      ) do
    {:ok, %{state | result: result, pending: nil}}
  end

  def complete(_input, state), do: {:ok, state}

  def reconcile(state),
    do: {:ok, state, Enum.map(state.desired -- state.alive, &spawn_worker/1)}

  def child_exit(tag, state) do
    pending = if match?(%{owner: ^tag}, state.pending), do: nil, else: state.pending
    {:ok, %{state | alive: List.delete(state.alive, tag), pending: pending}}
  end

  defp spawn_worker(tag),
    do: Directive.spawn_child(Handoff.Worker, tag, restart: :temporary)

  defp offer(request, owner, generation) do
    Directive.emit_to_child(
      owner,
      Handoff.signal("examples.research.handoff.worker.prepare", %{
        request: request,
        owner: owner,
        generation: generation
      })
    )
  end
end
