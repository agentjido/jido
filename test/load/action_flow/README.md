# Action and Flow load verification

Run `mix test.load test/load/action_flow` from the package root. The suite runs 200 fixed one-step workflows with
bounded concurrency. It verifies that each result keeps its own ID and input, every caller task stops, every supervised
execution task stops, and the shared execution supervisor returns to its starting child set.

Elapsed time is not a pass condition. Use the burn-in command for repeated fresh BEAM runs:

```sh
sh test/load/action_flow/burn_in.sh 10
```
