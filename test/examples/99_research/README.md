# Research probe test

This folder contains the executable evidence for the retained
[distributed-authority probe](../../../examples/99_research/99_02_distributed_authority/README.md).

```sh
mix test test/examples/99_research --include example --seed 0
```

The test starts local peer nodes. It proves the external fencing workaround.
It does not prove the missing Jido `DIST-03` contract.
