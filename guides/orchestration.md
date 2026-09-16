# Compose Agent systems

Use Flows for one executable graph. Use owned children for separate live Agents.
Use `Jido.Topology` to author and start a static system through DSL, Builder, or
Codec. The forms share validation and planning. Composition supports imports,
exports, bindings, keyed identities, and supervised activation.

Topology validates before startup and cleans up a partial start. Its Controller
can repair the declared system, add Agents, place one Agent on an exact known
node, and stop it. Lifecycle state enters an optional control Agent as normal
Signals. Node discovery, capacity choice, and rebalance policy belong in an
application or Plugin. The 1,000-worker example is a local scale check, not a
multi-host capacity claim. The old Pod mutation API is removed.

See the [Topology guide](https://github.com/agentjido/jido/blob/release/v3/examples/07_topology/README.md),
[child ownership](https://github.com/agentjido/jido/blob/release/v3/examples/05_multi_agent/README.md), and
[application scenarios](https://github.com/agentjido/jido/blob/release/v3/examples/08_applications/README.md).
