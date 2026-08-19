# Jido Examples

This folder is a scratch space for example project shapes and integration
patterns.

The goal is not polished documentation yet. The goal is to make the intended
developer experience concrete enough to critique.

## Current Conventions Under Test

- A `Jido.Pod` is the durable multi-agent runtime definition.
- A sibling domain/context module is the application-facing API.
- Phoenix controllers, LiveViews, and jobs call the domain/context module, not
  `Jido.Pod` directly.

## Examples

- `phoenix_issue_triage/`
  - A larger Phoenix-shaped project slice with a pod, facade/context module,
    sensors, custom actions, memory/thread usage, and live mutation.
