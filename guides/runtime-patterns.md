# Runtime patterns

Use one Signal for one Turn. Use saved IDs for work that must survive retries.
Keep durable intent in validated Agent or Plugin state. Let owned resources
perform the work and send completion through another Signal. Acknowledge work
in the same commit as its business result where the example requires it.

Use explicit child ownership and bounded concurrency. Distinguish a remote
disconnect from process death. Test startup, failure before commit, failure after
commit, recovery, duplicate results, stale attempts, and final cleanup.

See [Runtime examples](https://github.com/agentjido/jido/tree/v3-spike/examples/04_runtime/README.md) and
[Multi-agent examples](https://github.com/agentjido/jido/tree/v3-spike/examples/05_multi_agent/README.md).
