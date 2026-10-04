# Topology example tests

This folder mirrors the numbered learning path in
[the Topology examples](../../../examples/07_topology/README.md).

Run the section behavior tests:

```sh
mix test test/examples/07_topology --include example --seed 0
```

The Bus swarm test is a local scale fixture. The remaining tests check:

- Independent Agent state recovery with manual repair, and clean stops that
  remain stopped after reconciliation.
- Parent exit policy and logical binding repair without restarting stopped workers.
- Stable keyed identities and committed state after JSON transport and restart.
- Shared Bus replacement, component exports, and subscription recovery without
  Agent restarts.
- Plugin contributions, recovered subscriptions, unchanged source definitions,
  and process cleanup.
- Lifecycle Signals, placement-policy delegation, and additive target updates.
- Static extension lowering followed by normal Controller activation and cleanup.

Examples use public Jido and OTP APIs. Detailed restart limits, coordinator
failure races, and remote moves remain in the core and peer tests. The
[authoring suite](../../authoring/topology/README.md) checks live behavior across
all local definition forms.
