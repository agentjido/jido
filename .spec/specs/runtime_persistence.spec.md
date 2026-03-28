# Runtime Persistence

Current-truth contract for durable keyed runtimes and storage backends.

## Intent

This subject covers how Jido persists named runtimes, hibernates them on demand, and restores them from storage backends.

```spec-meta
id: jido.runtime_persistence
kind: subsystem
status: active
summary: Jido persists durable keyed runtimes through hibernate/thaw flows and pluggable storage backends.
surface:
  - guides/storage.md
  - lib/jido/persist.ex
  - lib/jido/storage.ex
  - lib/jido/storage
  - test/examples/persistence/checkpoint_restore_test.exs
  - test/examples/persistence/persistence_storage_test.exs
  - test/jido/integration/hibernate_thaw_test.exs
  - test/jido/persist_test.exs
  - test/jido/storage
```

## Requirements

```spec-requirements
- id: jido.runtime_persistence.hibernate_thaw
  statement: Jido shall support hibernate and thaw flows for durable keyed runtimes.
  priority: must
  stability: stable

- id: jido.runtime_persistence.storage_backends
  statement: Jido shall support pluggable storage backends for persisted runtime checkpoints and related state.
  priority: must
  stability: stable
```

## Verification

```spec-verification
- kind: guide_file
  target: guides/storage.md
  covers:
    - jido.runtime_persistence.hibernate_thaw
    - jido.runtime_persistence.storage_backends

- kind: command
  target: mix test test/jido/persist_test.exs test/jido/storage test/examples/persistence/checkpoint_restore_test.exs test/examples/persistence/persistence_storage_test.exs test/jido/integration/hibernate_thaw_test.exs
  execute: true
  covers:
    - jido.runtime_persistence.hibernate_thaw
    - jido.runtime_persistence.storage_backends
```
