# Example tests

Runnable source lives in the root [example catalog](../../examples/README.md).
Test folders follow that catalog, including [application examples](08_applications)
and [Plugin examples](09_plugins), plus the [persistence examples](10_persistence).
Every test uses `:example`, directly or through a shared case template. Do not
add a separate integration tag or a second copy of an existing assertion.

```sh
mix test                               # Excludes examples
mix test.examples                      # Runs all example tests
mix test test/examples/08_applications --include example --seed 0
mix test test/examples/10_persistence --include example --seed 0
```

The research suite contains the peer-based external fencing evidence for the
missing cluster-exclusive ownership contract.
Use the [testing guide](../../guides/testing.md) for full acceptance and coverage
commands. Detailed stable contracts stay in focused core tests.
