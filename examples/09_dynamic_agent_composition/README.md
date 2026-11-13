# 09 Dynamic Agent Composition

These examples cover Agent creation, local runtime ownership, request
correlation, adoption, and transfer decisions made during execution.

- [09_01 Logical Agent Lifecycle](09_01_child_lifecycle/README.md)
- [09_02 Correlated Requests](09_02_correlated_requests/README.md)
- [09_03 Process Replacement](09_03_orphan_adoption/README.md)
- [09_04 Independent Agents](09_04_independent_agents/README.md)
- [09_05 Logical Ownership Transfer](09_05_logical_ownership_transfer/README.md)
- [09_06 Shutdown Behavior](09_06_shutdown_behavior/README.md)

Independent runtime Agents and application-level logical ownership are
supported locally. The current public runtime does not provide dynamic child
adoption or transfer of OTP process ownership. Nested definition ownership is
covered by [10_04 Nested Agents](../10_declared_agent_topologies/10_04_nested_agents/README.md).
Remote placement and node-loss behavior are outside this suite.

```sh
mix test.examples examples/09_dynamic_agent_composition
```

The [Worker](support/worker.ex) supports local lifecycle and correlation.
These examples do not provide cluster ownership or automatic remote failover.

Compare [declared topology](../10_declared_agent_topologies/README.md) when members and
connections belong to a saved Agent definition. This section teaches child
creation and ownership decisions made during execution.
