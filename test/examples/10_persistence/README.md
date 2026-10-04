# Persistence example tests

This folder mirrors the numbered lessons in [the persistence examples](../../../examples/10_persistence/README.md).

Run the section:

`mix test test/examples/10_persistence --include example --seed 0`

The tests use public Jido APIs and deterministic local stores. They cover exact
byte replacement, Ref lifetime controls, idle thaw, and uncertain-write
cleanup. Test-only record changes and uncertain write results stay in
`test/support/persistence/`. Shared external adapter checks remain optional.
