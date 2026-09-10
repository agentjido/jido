# 06_03 Department Factory

An orchestrator runs one accepted goal through four persistent department
Agents and an explicit dependency plan.

## What you will learn

- How an Agent owns a fixed group of specialist child Agents.
- How stable attempt IDs and dependency state reject stale results.

## Read the code

Read [the orchestrator](orchestrator.ex), [the dependency plan](plan.ex), and
[the department Agent](department.ex). The longer
[design note](orchestrator-plan.md) explains the application policy.

## Run it

```sh
mix test test/examples/06_factory/06_03_department_factory --include example --seed 0
```

Expected result: Research and Design overlap, Build waits for both artifacts,
and Quality waits for Build.

## Important behavior

At most two department calls are active. Failure cancels other active calls.
Pause lets active calls finish, while cancel rejects their late results.

## Limits

The dependency graph is static application data. Active work is not recovered
after process or node loss.

## Files

- [Orchestrator Agent](orchestrator.ex)
- [Department Agent](department.ex)
- [Plan](plan.ex)
- [Tests](../../../test/examples/06_factory/06_03_department_factory/orchestrator_test.exs)
- [Section support](../support/)

Previous: [Three-Agent System](../06_02_three_agent_system/README.md) | Next: [Flow Factory](../06_04_flow_factory/README.md)
