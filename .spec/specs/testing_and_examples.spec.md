# Testing And Examples

Current-truth contract for Jido's testing guidance, support helpers, and runnable example suite.

## Intent

This subject covers the repository-level testing surface that keeps pure-agent tests, runtime integration tests, and runnable examples stable and usable for maintainers.

```spec-meta
id: jido.testing_and_examples
kind: subsystem
status: active
summary: Jido provides isolation-friendly test support and runnable examples for core public flows.
surface:
  - guides/testing.md
  - test
```

## Requirements

```spec-requirements
- id: jido.testing_and_examples.testing_guidance
  statement: Jido shall document testing patterns for pure logic and runtime integration.
  priority: must
  stability: stable

- id: jido.testing_and_examples.async_test_support
  statement: Jido shall provide test support for isolated instances and event-driven async assertions without sleep-based polling.
  priority: must
  stability: stable

- id: jido.testing_and_examples.runnable_examples
  statement: Jido shall keep runnable example and docs-example suites that exercise core public patterns.
  priority: must
  stability: stable
```

## Verification

```spec-verification
- kind: guide_file
  target: guides/testing.md
  covers:
    - jido.testing_and_examples.testing_guidance
    - jido.testing_and_examples.async_test_support
    - jido.testing_and_examples.runnable_examples

- kind: command
  target: mix test test/jido/docs_examples_test.exs test/examples
  execute: true
  covers:
    - jido.testing_and_examples.testing_guidance
    - jido.testing_and_examples.async_test_support
    - jido.testing_and_examples.runnable_examples
```
