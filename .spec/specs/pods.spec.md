# Pods

Current-truth contract for durable group-of-agents topology in Jido core.

## Intent

This subject covers Jido Pods as the durable topology layer for grouped agents, including eager and lazy activation, nested pods, and live mutation of a persisted topology snapshot.

```spec-meta
id: jido.pods
kind: subsystem
status: active
summary: Jido Pods provide durable topology, activation, nesting, and live mutation for grouped agents.
surface:
  - guides/pods.md
  - lib/jido/pod.ex
  - lib/jido/pod
  - test/examples/runtime/mutable_pod_runtime_test.exs
  - test/examples/runtime/nested_pod_runtime_test.exs
  - test/examples/runtime/nested_pod_scale_test.exs
  - test/examples/runtime/pod_runtime_test.exs
  - test/examples/runtime/pod_scale_test.exs
  - test/jido/pod
  - test/jido/pod/mutation
```

## Requirements

```spec-requirements
- id: jido.pods.durable_topology
  statement: Jido shall model a Pod as a durable topology snapshot for a named group of agents.
  priority: must
  stability: stable

- id: jido.pods.reconcile_and_lazy_activation
  statement: Jido shall reconcile eager pod members automatically and let lazy members start on demand through ensure operations.
  priority: must
  stability: stable

- id: jido.pods.nested_pods
  statement: Jido shall support nested pod topologies as part of the durable group model.
  priority: must
  stability: stable

- id: jido.pods.live_mutation
  statement: Jido shall support live add and remove mutation of pod topology while keeping the topology itself durable.
  priority: must
  stability: stable
```

## Verification

```spec-verification
- kind: guide_file
  target: guides/pods.md
  covers:
    - jido.pods.durable_topology
    - jido.pods.reconcile_and_lazy_activation
    - jido.pods.nested_pods
    - jido.pods.live_mutation

- kind: command
  target: mix test test/jido/pod test/jido/pod/mutation test/examples/runtime/pod_runtime_test.exs test/examples/runtime/nested_pod_runtime_test.exs test/examples/runtime/pod_scale_test.exs test/examples/runtime/nested_pod_scale_test.exs test/examples/runtime/mutable_pod_runtime_test.exs
  execute: true
  covers:
    - jido.pods.durable_topology
    - jido.pods.reconcile_and_lazy_activation
    - jido.pods.nested_pods
    - jido.pods.live_mutation
```
