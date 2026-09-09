# PERSIST-03 acceptance notes

```sh
mix test test/examples/99_research/99_08_indeterminate_write --include example --seed 0
```

The folder test proves that an uncertain stored write blocks output and later
Action evaluation on stale state. The deeper core suite also covers a confirmed
write and a raised callback after storage.

The test records Action execution separately from post-commit Signal delivery.
It confirms the stored revision before checking admission. No sleep, provider
request, database, or VM restart is used.

[Core tests](../../../jido/persistence/indeterminate_write_test.exs) ·
[Example](../../../../examples/99_research/99_08_indeterminate_write/README.md)
