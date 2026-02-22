# AGENTS.md - Jido Test Support Guide

## Intent
Provide stable, reusable testing patterns for pure agents, AgentServer runtime behavior, and multi-agent flows.

## Runtime Baseline
- Elixir `~> 1.18`
- OTP `27+` (release QA baseline)

## Commands
- `mix test`
- `mix test test/path/to/file_test.exs`
- `mix test --cover`
- `mix test --include example`

## Support Modules
- `JidoTest.Case`: isolated Jido instance per test (`jido`, `jido_pid` context)
- `JidoTest.Eventually`: polling helpers/macros (`eventually`, `assert_eventually`, `eventually_state`)
- `JidoTest.Support.TestTracer`: lightweight span capture for runtime assertions
- `JidoTest.TestAgents` and `JidoTest.TestActions`: canonical fixtures for behavior-level tests

## Standards
- Prefer behavior assertions over implementation/log assertions
- Avoid `Process.sleep/1`; use eventual assertions and monitored process lifecycle checks
- Keep tests focused and deterministic (single behavior per test where practical)
- Use unique IDs/helpers to avoid test cross-talk

## High-Value Coverage
- `cmd/2` immutability and directive emission semantics
- AgentServer signal routing and runtime directive execution
- Parent-child lifecycle (`SpawnAgent`, `StopChild`) and state synchronization
- StateOp behavior (`SetState`, `ReplaceState`, `DeleteKeys`, `SetPath`, `DeletePath`)

## Release Hygiene
- Keep test fixtures aligned with current directive/state-op/tool contracts
- Use Conventional Commits
- Update examples in `test/examples/` when behavior contracts change

## References
- `test/support/`
- `test/examples/`
- `../README.md`
- https://hexdocs.pm/jido
