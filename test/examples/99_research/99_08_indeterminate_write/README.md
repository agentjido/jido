# PERSIST-03 acceptance notes

```sh
mix test test/jido/persistence/indeterminate_write_test.exs --seed 0
```

All four tests pass. Two controls verify normal and uncertain writes. The
admission tests reject later Action evaluation after an uncertain reply or a
raised callback after storage. They retain the separate execution observation.

The test records Action execution separately from post-commit Signal delivery.
It confirms the stored revision before checking admission. No sleep, provider
request, database, or VM restart is used.

[Tests](../../../jido/persistence/indeterminate_write_test.exs) ·
[Example](../../../../lib/examples/99_research/99_08_indeterminate_write/README.md)
