# Package entry points for the dead-code analyzer. Tests are not roots.
%{
  public_api: [
    # Main package entry points and downstream authoring macros.
    "lib/jido.ex",
    "lib/jido/agent.ex",
    "lib/jido/agent_server.ex",
    "lib/jido/plugin.ex",
    "lib/jido/topology.ex",
    # Caller-selected authoring interfaces. Internal callers are not required.
    "lib/jido/agent/builder.ex",
    "lib/jido/agent/codec.ex",
    "lib/jido/topology/builder.ex",
    "lib/jido/topology/codec.ex",
    # Added to a downstream application's supervision tree.
    "lib/jido/topology/controller.ex",
    # Optional Plugins selected in a downstream Agent's plugins declaration.
    # use Jido.Plugin injects @behaviour; it is not a literal source attribute.
    "lib/jido/plugin/audit.ex",
    "lib/jido/plugin/dispatch.ex",
    "lib/jido/plugin/heartbeat.ex",
    "lib/jido/plugin/scheduler.ex",
    "lib/jido/plugin/sensor_manager.ex",
    "lib/jido/plugin/bus/client.ex",
    # Public Action routed by the caller to jido.scheduler.enqueue for durable delivery.
    "lib/jido/plugin/scheduler/enqueue.ex",
    "lib/jido/plugin/bus/manager.ex",
    # Public documentation namespace. No executable functions.
    "lib/jido/plugin/bus.ex",
    # Caller-selected storage contract; implementations are reached by behaviour edges.
    "lib/jido/persistence/adapter.ex",
    # Optional application-owned data API.
    "lib/jido/thread.ex"
  ],
  roots: [
    {"lib/jido/application.ex", "Started by Mix application mod: {Jido.Application, []}"},
    {"lib/jido/id.ex",
     "Called by factory examples outside the core audit: Factory.IEx and Factory.FlowFactory. Removing it fails compile --warnings-as-errors."}
  ]
}
