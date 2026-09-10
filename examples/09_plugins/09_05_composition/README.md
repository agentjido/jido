# 09_05 Composition

One Agent combines a pure tenant input with a live authorization input.

## What you will learn

- How each Plugin owns separate `prepared` and `runtime` input slots.
- How pure preparation and live admission compose before route execution.
- How an Action explicitly selects the package inputs that it needs.
- How one rejection prevents all executable work.

## Run it

```sh
mix test test/examples/09_plugins/09_05_composition --include example --seed 0
```

The example does not use a shared mutable context. Each Plugin has one isolated
input record with a pure slot and a live slot.

Previous: [Secure Signal](../09_04_secure_signal/README.md) | Next: [State Middleware](../09_06_state_middleware/README.md)
