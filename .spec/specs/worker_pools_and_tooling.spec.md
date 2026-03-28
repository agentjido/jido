# Worker Pools And Tooling

Current-truth contract for pooled execution and install or generator tooling around Jido.

## Intent

This subject covers the operational tooling that helps applications adopt Jido and scale recurring runtime work.

```spec-meta
id: jido.worker_pools_and_tooling
kind: subsystem
status: active
summary: Jido provides worker-pool execution patterns and install or generator tooling for adoption.
surface:
  - guides/worker-pools.md
  - lib/jido/agent/worker_pool.ex
  - lib/jido/igniter
  - lib/jido/util.ex
  - lib/mix/tasks
  - test/jido/agent_pool_test.exs
  - test/jido/igniter
  - test/jido/scheduler_test.exs
  - test/jido/supervisor_test.exs
```

## Requirements

```spec-requirements
- id: jido.worker_pools_and_tooling.worker_pools
  statement: Jido shall provide worker-pool patterns for reusable pooled agent execution.
  priority: should
  stability: stable

- id: jido.worker_pools_and_tooling.tooling
  statement: Jido shall provide install and generator tooling that helps applications adopt the framework.
  priority: should
  stability: stable
```

## Verification

```spec-verification
- kind: guide_file
  target: guides/worker-pools.md
  covers:
    - jido.worker_pools_and_tooling.worker_pools

- kind: command
  target: mix test test/jido/agent_pool_test.exs test/jido/igniter test/jido/scheduler_test.exs test/jido/supervisor_test.exs
  execute: true
  covers:
    - jido.worker_pools_and_tooling.worker_pools
    - jido.worker_pools_and_tooling.tooling
```
