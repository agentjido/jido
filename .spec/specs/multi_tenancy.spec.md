# Multi-Tenancy

Current-truth contract for partition-based logical multi-tenancy in Jido.

## Intent

This subject covers Jido's shared-instance tenancy model, where partitions namespace runtime identity and pods become the durable tenant workspace unit.

```spec-meta
id: jido.multi_tenancy
kind: subsystem
status: active
summary: Jido supports shared-instance logical multi-tenancy through partitions and pod-first tenancy boundaries.
surface:
  - guides/multi-tenancy.md
  - lib/jido.ex
  - lib/jido/agent_server/child_info.ex
  - lib/jido/agent_server/parent_ref.ex
  - lib/jido/pod/runtime.ex
  - test/examples/runtime/partitioned_pod_runtime_test.exs
  - test/jido/agent_server/hierarchy_test.exs
  - test/jido/jido_test.exs
  - test/jido/pod/runtime_test.exs
  - test/jido/telemetry_test.exs
```

## Requirements

```spec-requirements
- id: jido.multi_tenancy.partition_namespace
  statement: Jido shall support partition as a logical namespace boundary for runtimes in a shared instance.
  priority: must
  stability: stable

- id: jido.multi_tenancy.pod_first_tenancy
  statement: Jido shall treat Pods as the durable tenant or workspace unit in the shared-instance tenancy model.
  priority: must
  stability: stable

- id: jido.multi_tenancy.partition_propagation
  statement: Jido shall propagate partition context through pod membership, hierarchy, persistence, and runtime lookup paths by default.
  priority: must
  stability: stable
```

## Verification

```spec-verification
- kind: guide_file
  target: guides/multi-tenancy.md
  covers:
    - jido.multi_tenancy.partition_namespace
    - jido.multi_tenancy.pod_first_tenancy
    - jido.multi_tenancy.partition_propagation

- kind: command
  target: mix test test/examples/runtime/partitioned_pod_runtime_test.exs test/jido/pod/runtime_test.exs test/jido/agent_server/hierarchy_test.exs test/jido/jido_test.exs test/jido/telemetry_test.exs
  execute: true
  covers:
    - jido.multi_tenancy.partition_namespace
    - jido.multi_tenancy.pod_first_tenancy
    - jido.multi_tenancy.partition_propagation
```
