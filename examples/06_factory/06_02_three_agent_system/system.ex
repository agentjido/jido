defmodule Jido.Examples.Factory.System do
  @moduledoc "Owns the conversation and factory Agents. Relays factory event Signals to the conversation."
  use Jido.Agent, name: "factory_system"

  alias Jido.Agent.Directive
  alias Jido.Examples.Factory.{Conversation, Orchestrator, Protocol, Workshop}

  agent do
    schema Zoi.object(%{
             started: Zoi.boolean() |> Zoi.default(false),
             mode: Zoi.enum([:workshop, :departments]) |> Zoi.default(:workshop),
             events: Zoi.list(Zoi.map()) |> Zoi.default([]),
             child_exits: Zoi.list(Zoi.string()) |> Zoi.default([])
           })
  end

  routes do
    signal_source "/examples/factory/system"

    route "examples.factory.system.boot" do
      action input,
        schema:
          Zoi.object(%{
            mode: Zoi.enum([:workshop, :departments]) |> Zoi.default(:workshop),
            step_delay_ms: Zoi.integer() |> Zoi.min(1) |> Zoi.default(2_000)
          }),
        context: context do
        Jido.Examples.Factory.System.boot_state(input, context)
      end

      define :boot, args: [{:optional, :mode}]
    end

    route "examples.factory.event" do
      action input,
        schema: Jido.Examples.Factory.Protocol.event_schema(),
        context: context do
        events = Enum.take(context.agent_state.events ++ [input], -100)
        directive = Jido.Agent.Directive.emit_to_child("conversation", context.signal)
        {:ok, %{context.agent_state | events: events}, [directive]}
      end
    end

    route "jido.agent.child.started", Jido.Examples.Support.KeepState

    route "jido.agent.child.exit" do
      action %{tag: tag}, context: context do
        {:ok, %{context.agent_state | child_exits: context.agent_state.child_exits ++ [tag]}}
      end
    end
  end

  @doc false
  def boot_state(_, %{agent_state: %{started: true}}),
    do: Protocol.invalid("System is already started")

  def boot_state(input, %{agent_state: state, agent_id: id}) do
    factory = if input.mode == :departments, do: Orchestrator, else: Workshop

    factory_opts =
      if input.mode == :workshop,
        do: %{initial_state: %{step_delay_ms: input.step_delay_ms}},
        else: %{}

    boot =
      if input.mode == :departments,
        do: Orchestrator.boot_signal!(),
        else: Workshop.boot_signal!()

    directives = [
      Directive.spawn_child(Conversation, "conversation",
        opts: %{initial_state: %{factory_id: "#{id}/factory", factory_mode: input.mode}}
      ),
      Directive.spawn_child(factory, "factory", opts: factory_opts),
      Directive.emit_to_child("factory", boot)
    ]

    {:ok, %{state | started: true, mode: input.mode}, directives}
  end
end
