# Topology Plugin contribution

The Agent declares one Plugin package. Its Topology facet contributes one Bus
and connects that Agent declaration to the Bus. The source Topology does not
repeat this wiring.

`Jido.Topology.new/1` validates the static source and does not call Topology
contribution callbacks. `Jido.Topology.instantiate/2` asks each Topology facet
for its pure static contribution before it builds the local plan. This
operation starts no Jido process.

The common Topology validator checks the combined entries. Duplicate keys,
unknown endpoints, duplicate subscriptions, and graph cycles fail before a
Controller can start the plan.

The facet owns only static contribution. It cannot start an Agent, create a
runtime Plugin process, persist state, replace the Controller target, or grant
distributed write authority.
