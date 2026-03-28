# Runtime Lifecycle

Current-truth contract for AgentServer runtime hosting, hierarchy management, waiting, and durable instance management.

## Intent

This subject covers the live runtime surface that hosts agents, coordinates children, and manages keyed instances and async waiting without weakening the pure agent boundary.

```spec-meta
id: jido.runtime_lifecycle
kind: subsystem
status: active
summary: Jido runtime lifecycle is hosted by AgentServer and coordinated through hierarchy, await, and instance-management APIs.
surface:
  - guides/runtime.md
  - guides/await.md
  - guides/orchestration.md
  - guides/orphans.md
  - guides/runtime-patterns.md
  - lib/jido/agent_server.ex
  - lib/jido/agent_server
  - lib/jido/application.ex
  - lib/jido/await.ex
  - lib/jido/agent/instance_manager.ex
  - lib/jido/agent/instance_manager
  - lib/jido/runtime_store.ex
  - test/examples/runtime/hierarchical_agents_test.exs
  - test/examples/runtime/orphan_lifecycle_test.exs
  - test/examples/runtime/parent_child_test.exs
  - test/examples/runtime/spawn_agent_test.exs
  - test/jido/agent/instance_manager_test.exs
  - test/jido/agent_server
  - test/jido/await_coverage_test.exs
  - test/jido/await_test.exs
  - test/jido/instance_test.exs
  - test/jido/runtime_store_test.exs
```

## Requirements

```spec-requirements
- id: jido.runtime_lifecycle.agent_server_runtime
  statement: Jido shall host live agents inside AgentServer processes that execute directives, expose runtime status, and isolate agent state from transport concerns.
  priority: must
  stability: stable

- id: jido.runtime_lifecycle.hierarchy_and_orphans
  statement: Jido shall support tracked child hierarchies, adoption, explicit orphan policies, and child stop control within the runtime.
  priority: must
  stability: stable

- id: jido.runtime_lifecycle.await_coordination
  statement: Jido shall provide event-driven await APIs for async coordination instead of relying on sleep-based polling.
  priority: must
  stability: stable

- id: jido.runtime_lifecycle.instance_management
  statement: Jido shall provide durable keyed instance-management patterns for starting, locating, hibernating, and thawing named runtimes.
  priority: must
  stability: stable
```

## Verification

```spec-verification
- kind: guide_file
  target: guides/runtime.md
  covers:
    - jido.runtime_lifecycle.agent_server_runtime

- kind: guide_file
  target: guides/orphans.md
  covers:
    - jido.runtime_lifecycle.hierarchy_and_orphans

- kind: guide_file
  target: guides/await.md
  covers:
    - jido.runtime_lifecycle.await_coordination

- kind: guide_file
  target: guides/runtime-patterns.md
  covers:
    - jido.runtime_lifecycle.instance_management

- kind: command
  target: mix test test/jido/agent_server test/jido/await_test.exs test/jido/await_coverage_test.exs test/jido/agent/instance_manager_test.exs test/jido/instance_test.exs test/jido/runtime_store_test.exs test/examples/runtime/parent_child_test.exs test/examples/runtime/hierarchical_agents_test.exs test/examples/runtime/orphan_lifecycle_test.exs test/examples/runtime/spawn_agent_test.exs
  execute: true
  covers:
    - jido.runtime_lifecycle.agent_server_runtime
    - jido.runtime_lifecycle.hierarchy_and_orphans
    - jido.runtime_lifecycle.await_coordination
    - jido.runtime_lifecycle.instance_management
```
