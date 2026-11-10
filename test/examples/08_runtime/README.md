# 08 Runtime Tests

This folder mirrors the numbered learning path in
[the runtime examples](../../../examples/08_runtime/README.md).

Run the section behavior tests:

```sh
mix test test/examples/08_runtime --include example --seed 0
```

The tests use public Jido APIs and deterministic local adapters. Test-only
barriers stay in test support and do not appear in example Actions or Flows.

Definition Changes (`08_12`) proves pure/live separation, final Diff, route precedence after mutation, rejected-batch isolation, and cancelled edits.
