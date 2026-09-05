# Compose Agent systems

Use Flows for one executable graph. Use owned children for separate live Agents.
Use `Jido.Topology` to author and start a static system through DSL, Builder, or
Codec. The forms share validation and planning. Composition supports imports,
exports, bindings, keyed identities, and local supervision.

Topology validates before startup and cleans up a partial start. Its controller
can repair the declared system and stop it. The 1,000-worker example checks each
worker and final cleanup. This is a local scale check, not a multi-host capacity
claim. The old Pod mutation API is removed.

See the [Topology guide](../lib/examples/07_topology/README.md),
[bounded workers](../lib/examples/05_multi_agent/README.md), and
[application scenarios](../test/integration/README.md).
