# 08_08 Elastic Group

A controller applies a bounded scale policy, reclaims interrupted work, and
drains temporary workers back to a minimum group.

## What you will learn

- How stable child identity and attempt numbers protect recovered work.
- How control Signals coordinate scale-up, drain, stop, and monitoring.

## Read the code

Read [the controller Agent](elastic_group.ex), [its state policy](controller_state.ex),
[the worker](worker.ex), [the environment](environment.ex),
[the monitor](monitor.ex), then [the Signal builders](signals.ex).

## Run it

```sh
mix test test/examples/08_applications/08_08_elastic_group --include example --seed 0
```

Expected result: demand scales the group from two to ten workers, killed work
restarts at a new attempt, duplicate results do not commit, and idle workers
drain back to two.

## Important behavior

The controller stores assignments, attempts, and desired worker IDs. The
environment accepts one result per task. A worker stops only after it reports
that its drain is complete.

## Limits

This deterministic threshold policy is not a Jido autoscaler API. It does not
restore controller membership after a controller restart or enforce a drain
deadline.

## Files

- [Controller Agent](elastic_group.ex)
- [Controller state policy](controller_state.ex)
- [Worker](worker.ex)
- [Environment](environment.ex)
- [Monitor](monitor.ex)
- [Signals](signals.ex)
- [Shared Bus input Plugin](../support/bus_input.ex)
- [Tests](../../../test/examples/08_applications/08_08_elastic_group/elastic_group_test.exs)

Previous: [Fixed Group](../08_07_fixed_group/README.md) | Next: [Prepared Plugin Input](../../09_plugins/09_01_prepared_input/README.md)
