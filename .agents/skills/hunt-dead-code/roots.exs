# Package entry points for the dead-code analyzer. Tests are not roots.
%{
  public_api: [
    # Main package entry points and downstream authoring macros.
    "lib/jido.ex",
    "lib/jido/agent.ex",
    "lib/jido/agent_server.ex",
    "lib/jido/plugin.ex",
    # Caller-selected authoring interfaces. Internal callers are not required.
    "lib/jido/agent/codec.ex",
    "lib/jido/agent/view.ex",
    # Optional Plugins selected in a downstream Agent's plugins declaration.
    # use Jido.Plugin injects @behaviour; it is not a literal source attribute.
    "lib/jido/agent/plugin/fsm.ex",
    "lib/jido/plugin/audit.ex",
    "lib/jido/plugin/heartbeat.ex",
    "lib/jido/plugin/scheduler.ex",
    "lib/jido/plugin/scheduler/dsl.ex",
    "lib/jido/plugin/sensor_manager.ex",
    "lib/jido/plugin/bus/client.ex",
    "lib/jido/plugin/bus/manager.ex",
    # Public documentation namespace. No executable functions.
    "lib/jido/plugin/bus.ex",
    # Caller-selected storage contract; implementations are reached by behaviour edges.
    "lib/jido/persistence/adapter.ex",
    # Called from a downstream Ecto migration. The package does not invoke it.
    "lib/jido/persistence/ecto/migration.ex"
  ],
  roots: [
    {"lib/jido/application.ex", "Started by Mix application mod: {Jido.Application, []}"},
    {"lib/jido/agent_server/durable_turn/wait_host.ex",
     "Called by Jido.AgentServer.DurableTurn through an alias rooted at __MODULE__."},
    {"lib/jido/id.ex",
     "Called by factory examples outside the core audit: Factory.IEx and Factory.FlowFactory. Removing it fails compile --warnings-as-errors."}
  ]
}
