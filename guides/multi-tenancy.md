# Instance and partition scope

Use separate named Jido instances for separate infrastructure ownership. Within
an instance, pass `partition: value` consistently to startup, lookup, listing,
parent binding, and persistence operations. The same Agent ID can exist in
different partitions. Omitted partition means the default scope.

An ID is not a security credential. Applications must authorize requests before
routing them into a tenant scope. Persistence records validate instance, module,
partition, and Agent ID. Remote node connections do not add cluster-exclusive
ownership.

See [instance scope checks](../test/jido/instance_test.exs) and
[persistence tests](../test/jido/persistence_test.exs).
