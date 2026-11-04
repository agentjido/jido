# Runtime property checks

This suite generates AgentServer command histories. Each history checks the
same independent state model before and after File-backed hibernation.

Run the short property budget:

```console
mix test.property test/property/runtime
```

Run the larger fuzz budget:

```console
mix test.fuzz test/property/runtime
```

The tests use temporary local storage. They do not use a network service.
