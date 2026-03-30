# Debugging And Errors

Current-truth contract for interactive debugging and structured public error behavior.

## Intent

This subject covers how Jido helps maintainers diagnose live issues and rely on stable error shapes across runtime execution.

```spec-meta
id: jido.debugging_and_errors
kind: subsystem
status: active
summary: Jido provides runtime debugging tools and structured public error contracts.
surface:
  - guides/debugging.md
  - guides/errors.md
  - lib/jido/debug.ex
  - lib/jido/error.ex
  - test/jido/debug_integration_test.exs
  - test/jido/debug_test.exs
  - test/jido/error_coverage_test.exs
  - test/jido/error_test.exs
```

## Requirements

```spec-requirements
- id: jido.debugging_and_errors.runtime_debugging
  statement: Jido shall provide runtime debugging facilities for inspecting recent execution and runtime state.
  priority: must
  stability: stable

- id: jido.debugging_and_errors.structured_errors
  statement: Jido shall expose structured public error contracts across actions, directives, and signal processing.
  priority: must
  stability: stable
```

## Verification

```spec-verification
- kind: guide_file
  target: guides/debugging.md
  covers:
    - jido.debugging_and_errors.runtime_debugging

- kind: guide_file
  target: guides/errors.md
  covers:
    - jido.debugging_and_errors.structured_errors

- kind: command
  target: mix test test/jido/debug_test.exs test/jido/debug_integration_test.exs test/jido/error_test.exs test/jido/error_coverage_test.exs
  execute: true
  covers:
    - jido.debugging_and_errors.runtime_debugging
    - jido.debugging_and_errors.structured_errors
```
