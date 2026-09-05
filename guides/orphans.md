# Owned Agents

Use `SpawnAgent` to create an owned child with a stable tag. Use `StopChild` or
`AgentServer.stop_child/3` to stop it. Inspect `AgentServer.children/1`.
Parent bindings and child monitors belong to the runtime. Keep process handles
out of persisted Agent state.

Child startup, shutdown, replacement, and parent death follow the configured
ownership policy. Explicit adoption uses `AgentServer.adopt_parent/2` and
`adopt_child/4`; it is not a general topology-edit API.

Remote placement uses real nodes. Disconnect and death are separate events.
A remote Agent can still run while unreachable. Reconnect and replacement need
an explicit ownership decision. Local Registry uniqueness and storage revision
fencing do not establish cluster-exclusive ownership.

See the [Multi-agent examples](../lib/examples/05_multi_agent/README.md) and
[remote lifecycle tests](../test/jido/agent/remote_lifecycle_test.exs).
