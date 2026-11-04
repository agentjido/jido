# Action and Flow benchmark smoke checks

The smoke check runs every Action and Flow benchmark with its `quick` profile.
It checks result data, task cleanup, fresh-VM ReAct execution, report shape,
environment data, and the source fingerprint. It does not fail on a timing or
memory value.

Run it with:

```sh
mix test.bench test/bench/action_flow
```
