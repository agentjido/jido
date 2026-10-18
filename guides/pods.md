# Topology after V2 Pods

The V2 Pod runtime and mutation planner are removed. A normal `Jido.Agent`
definition now contains its topology. Agent mutation directives change the
saved definition; AgentServer applies the accepted change under its OTP supervisor.

Use [the topology examples](../examples/07_topology/README.md) for named members,
nested ownership, local Bus delivery, and member mutations. Application queue,
scaling, and drain policy belongs above that contract. The old source remains
in Git history. See [orchestration](orchestration.md) for the runtime boundary.
