defmodule Jido.Examples.Factory.System.Boot do
  @moduledoc false
  use Jido.Action,
    name: "factory_system_boot",
    schema:
      Zoi.object(%{
        mode: Zoi.enum([:workshop, :departments]) |> Zoi.default(:workshop),
        step_delay_ms: Zoi.integer() |> Zoi.min(1) |> Zoi.default(2_000)
      })

  alias Jido.Agent.Directive
  alias Jido.Examples.Factory.{Conversation, Orchestrator, Protocol, Workshop}

  def run(input, %{agent_state: %{started: false} = state, agent_id: id}) do
    factory = if input.mode == :departments, do: Orchestrator, else: Workshop

    factory_opts =
      if input.mode == :workshop,
        do: %{initial_state: %{step_delay_ms: input.step_delay_ms}},
        else: %{}

    directives = [
      Directive.spawn_agent(Conversation, "conversation",
        opts: %{initial_state: %{factory_id: "#{id}/factory", factory_mode: input.mode}}
      ),
      Directive.spawn_agent(factory, "factory", opts: factory_opts)
    ]

    boot =
      if input.mode == :departments,
        do: Orchestrator.boot_signal!(),
        else: Workshop.boot_signal!()

    directives = directives ++ [Directive.emit_to_child("factory", boot)]

    {:ok, %{state | started: true, mode: input.mode}, directives}
  end

  def run(_, _), do: Protocol.invalid("System is already started")
end

defmodule Jido.Examples.Factory.System do
  @moduledoc "Owns the conversation and factory Agents. Relays factory event Signals to the conversation."
  use Jido.Agent, name: "factory_system"

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

    route "factory.system.boot", __MODULE__.Boot do
      define :boot, args: [{:optional, :mode}]
    end

    route "factory.system.ready", Jido.Examples.KeepState do
      define :ready
    end

    route "factory.event" do
      action input,
        name: "factory_system_event",
        schema: Jido.Examples.Factory.Protocol.event_schema(),
        context: context do
        events = Enum.take(context.agent_state.events ++ [input], -100)
        directive = Jido.Agent.Directive.emit_to_child("conversation", context.signal)
        {:ok, %{context.agent_state | events: events}, [directive]}
      end
    end

    route "jido.agent.child.started", Jido.Examples.KeepState

    route "jido.agent.child.exit" do
      action %{tag: tag}, name: "factory_system_exit", context: context do
        {:ok, %{context.agent_state | child_exits: context.agent_state.child_exits ++ [tag]}}
      end
    end
  end
end
