# Configuration And Discovery

Current-truth contract for runtime configuration defaults and discovery APIs.

## Intent

This subject covers how Jido instances are configured and how runtime metadata can be discovered and introspected by applications and tooling.

```spec-meta
id: jido.configuration_and_discovery
kind: subsystem
status: active
summary: Jido exposes configuration defaults and discovery APIs for actions, sensors, and runtime metadata.
surface:
  - guides/configuration.md
  - guides/discovery.md
  - lib/jido/config/defaults.ex
  - lib/jido/discovery.ex
  - test/jido/config
  - test/jido/discovery_test.exs
```

## Requirements

```spec-requirements
- id: jido.configuration_and_discovery.configuration_defaults
  statement: Jido shall document and expose configuration defaults suitable for local development and deployment environments.
  priority: must
  stability: stable

- id: jido.configuration_and_discovery.discovery_introspection
  statement: Jido shall provide discovery and introspection APIs for actions, sensors, and related runtime metadata.
  priority: should
  stability: stable
```

## Verification

```spec-verification
- kind: guide_file
  target: guides/configuration.md
  covers:
    - jido.configuration_and_discovery.configuration_defaults

- kind: guide_file
  target: guides/discovery.md
  covers:
    - jido.configuration_and_discovery.discovery_introspection

- kind: command
  target: mix test test/jido/config test/jido/discovery_test.exs
  execute: true
  covers:
    - jido.configuration_and_discovery.configuration_defaults
    - jido.configuration_and_discovery.discovery_introspection
```
