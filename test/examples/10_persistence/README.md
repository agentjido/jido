# Persistence example tests

This folder mirrors the numbered lessons in [the persistence examples](../../../examples/10_persistence/README.md).

Run the section:

`mix test test/examples/10_persistence --include example --seed 0`

The tests use public Jido APIs. Test-only record changes and uncertain write results stay in `test/support/persistence/`.
