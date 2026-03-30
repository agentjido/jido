# Thread Memory And Identity

Current-truth contract for Jido's persistent conversational and profile-oriented capability plugins.

## Intent

This subject covers the built-in capability plugins that keep thread journals, memory state, and identity state durable across runtime restarts.

```spec-meta
id: jido.thread_memory_identity
kind: subsystem
status: active
summary: Jido provides persistent thread, memory, and identity capabilities as structured plugins.
surface:
  - guides/storage.md
  - lib/jido/thread.ex
  - lib/jido/thread
  - lib/jido/memory.ex
  - lib/jido/memory
  - lib/jido/identity.ex
  - lib/jido/identity
  - test/examples/persistence/default_plugins_persistence_test.exs
  - test/examples/plugins/identity_plugin_test.exs
  - test/examples/plugins/memory_plugin_test.exs
  - test/examples/plugins/thread_plugin_test.exs
  - test/jido/identity
  - test/jido/memory
  - test/jido/thread
```

## Requirements

```spec-requirements
- id: jido.thread_memory_identity.thread_journal
  statement: Jido shall provide a persistent thread capability for structured conversational or event journals.
  priority: must
  stability: stable

- id: jido.thread_memory_identity.memory_capability
  statement: Jido shall provide a persistent memory capability for durable agent memory state.
  priority: must
  stability: stable

- id: jido.thread_memory_identity.identity_capability
  statement: Jido shall provide a persistent identity capability for durable agent identity and profile state.
  priority: must
  stability: stable
```

## Verification

```spec-verification
- kind: guide_file
  target: guides/storage.md
  covers:
    - jido.thread_memory_identity.thread_journal
    - jido.thread_memory_identity.memory_capability
    - jido.thread_memory_identity.identity_capability

- kind: command
  target: mix test test/jido/thread test/jido/memory test/jido/identity test/examples/plugins/thread_plugin_test.exs test/examples/plugins/memory_plugin_test.exs test/examples/plugins/identity_plugin_test.exs test/examples/persistence/default_plugins_persistence_test.exs
  execute: true
  covers:
    - jido.thread_memory_identity.thread_journal
    - jido.thread_memory_identity.memory_capability
    - jido.thread_memory_identity.identity_capability
```
