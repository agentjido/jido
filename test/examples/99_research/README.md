# Research probe tests

These tests provide the executable evidence for the
[research probes](../../../examples/99_research/README.md).

```sh
mix test test/examples/99_research --include example --seed 0
```

Every probe test uses the `:example` tag. The distributed-authority tests also
start local peer nodes. Test-only barriers and blocking Actions stay in
`test/examples/support/`; research source uses public Jido APIs.
