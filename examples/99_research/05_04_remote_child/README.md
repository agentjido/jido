# 05_04 Remote Agent Boundary

Status: unsupported remote placement and node-loss lifecycle.

Jido currently starts Agents locally. It does not provide remote placement,
automatic remote replacement, cluster ownership, or a node-loss lifecycle
contract. A remote start request is rejected before commit.

Read [the rejection test](../../../test/examples/99_research/05_04_remote_child/remote_start_test.exs).

```sh
mix test test/examples/99_research/05_04_remote_child --include example --seed 0
```

Expected result: the remote request leaves state, revision, and owned Agents
unchanged. This test does not establish remote lifecycle support. Former
remote-success proposals and the duplicate `05_05` entry were removed; their
numbers are not reused.

Use [Owned Agent Lifecycle](../../05_multi_agent/05_01_child_lifecycle/README.md)
for supported local work. See [Distributed Authority](../99_02_distributed_authority/README.md)
for the separate external-fencing research probe.
