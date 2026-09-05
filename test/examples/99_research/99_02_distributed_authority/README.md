# DIST-03 acceptance notes

The enabled two-node test proves cross-node restore and stale-revision
rejection. Its second assertion exposes the missing cluster owner claim:

```shell
mix test test/jido/agent/distributed_authority_test.exs --seed 0
```

Define the authority and partition policy before changing the assertion.

[Capability notes](../../../../lib/examples/99_research/99_02_distributed_authority/README.md) ·
[Evidence](../../../../docs/examples/dist-03-results.md)
