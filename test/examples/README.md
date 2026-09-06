# Example tests

Runnable source lives in the root [example catalog](../../examples/README.md).
Test folders follow that catalog, including [application examples](08_applications).
Every test uses `:example`, directly or through a shared case template. Do not
add a separate integration tag or a second copy of an existing assertion.

```sh
mix test                               # Excludes examples
mix examples --seed 0                  # Runs all example tests
mix test test/examples/08_applications --include example --seed 0
```

The research suite includes enabled failures for proposed core features.
Use the [testing guide](../../guides/testing.md) for full acceptance and coverage
commands. A folder with only a README links to a core test that already owns
those assertions.
