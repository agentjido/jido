# Load catalog

`catalog.yml` owns the bounded offline load families. It maps each workload to
its primary quality component, owner, limiter, exact command, bound, and
executable evidence. Run both families with:

```text
mix test.load
```

The required gate checks completion and cleanup. It does not use a portable
wall-clock threshold. The longer Action and Flow burn-in command remains
explicit and opt-in.
