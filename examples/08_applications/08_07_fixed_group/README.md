# 08_07 Fixed Group

A controller owns one environment and three stable workers that exchange
targeted work through a local Signal Bus.

## What you will learn

- How child Directives express stable application roles and ownership.
- How Bus delivery, target identity, restart, and committed worker state fit together.

## Read the code

Read [the controller](fixed_group.ex), [the worker](worker.ex),
[the environment](environment.ex), then [the Signal builders](signals.ex).

## Run it

```sh
mix test test/examples/08_applications/08_07_fixed_group --include example --seed 0
```

Expected result: work is distributed evenly, a killed worker restarts with its
state and stable ID, more work completes, and all children stop with the owner.

## Important behavior

The Bus broadcasts work. Each worker accepts only work that matches its group,
generation, and target ID. PIDs never enter Agent state.

## Limits

This is application policy, not a Jido group API. It does not reconcile a
restarted controller or resize the group.

## Files

- [Controller](fixed_group.ex)
- [Worker](worker.ex)
- [Environment](environment.ex)
- [Signals](signals.ex)
- [Shared Bus input Plugin](../support/bus_input.ex)
- [Tests](../../../test/examples/08_applications/08_07_fixed_group/fixed_group_test.exs)

Previous: [Purpose Loop](../08_06_purpose_loop/README.md) | Next: [Elastic Group](../08_08_elastic_group/README.md)
