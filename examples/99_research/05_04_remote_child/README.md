# 05_04_remote_child research

Status: unsupported. The folder keeps its original example number.

The `.exs` files retain the former remote placement and lifecycle proposal.
They use old APIs and are not loaded by the SDK example suite. Do not run them
as current API examples. No remote Agent start or node-loss lifecycle guarantee
is implemented by the current local AgentServer runtime.

The current contract rejects a remote Agent start before commit.
[The rejection test](../../../test/examples/99_research/05_04_remote_child/remote_start_test.exs)
checks that state, revision, and owned children remain unchanged.

Run that check from the Jido package:

```sh
mix test test/examples/99_research/05_04_remote_child --include example --seed 0
```

Use the [local lifecycle example](../../05_multi_agent/05_01_child_lifecycle/README.md)
for the supported local ownership contract.
