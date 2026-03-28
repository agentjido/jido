# Integrations And Migration

Current-truth contract for framework integration guidance and migration guidance.

## Intent

This subject covers the public guidance Jido provides for adopting the framework inside larger application stacks and upgrading from the prior runtime model.

```spec-meta
id: jido.integrations_and_migration
kind: subsystem
status: active
summary: Jido documents framework integrations and the migration path from the 1.x runtime model.
surface:
  - guides/phoenix-integration.md
  - guides/ash-integration.md
  - guides/migration.md
  - test/jido/docs_examples_test.exs
  - test/jido/integration
```

## Requirements

```spec-requirements
- id: jido.integrations_and_migration.framework_guides
  statement: Jido shall document integration paths for Phoenix and Ash-based applications.
  priority: should
  stability: stable

- id: jido.integrations_and_migration.migration_guidance
  statement: Jido shall document how maintainers migrate from the 1.x runtime model to the current instance-scoped runtime model.
  priority: must
  stability: stable
```

## Verification

```spec-verification
- kind: guide_file
  target: guides/phoenix-integration.md
  covers:
    - jido.integrations_and_migration.framework_guides

- kind: guide_file
  target: guides/ash-integration.md
  covers:
    - jido.integrations_and_migration.framework_guides

- kind: guide_file
  target: guides/migration.md
  covers:
    - jido.integrations_and_migration.migration_guidance

- kind: command
  target: mix test test/jido/docs_examples_test.exs test/jido/integration
  execute: true
  covers:
    - jido.integrations_and_migration.framework_guides
    - jido.integrations_and_migration.migration_guidance
```
