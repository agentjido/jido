# Recover a durable topology handoff

A team sends a ticket assignment to one declared responder. The team commits
the send while the responder is quiesced. When the team activates again, it
retries the saved send and the responder records one assignment.

```sh
mix test.examples examples/13_durable_execution/13_14_topology_handoff
```

See [Durable Topology](../../../guides/durability/durable-topology.md)
for the acceptance and retry rules. A downstream external effect has its own
recovery contract.
