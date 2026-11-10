# ADR 0001: Keep one Mix project and one OTP application

- Status: Accepted
- Date: 2026-11-03

## Context

Jido V3 consolidates `jido`, `jido_action`, `jido_signal`, and `jido_ai`. Separate Mix projects and OTP application roots would keep package boundaries inside the consolidated runtime. They would also split startup ownership.

## Decision

Use `jido/` as the only Mix project. Use `:jido` as the only OTP application. Use `Jido.Application` as the only application composition root.

Represent subsystem startup work as children or initialization steps of `Jido.Application`. Do not add application roots for Action, Signal, AI, or another namespace.

Keep internal boundaries with `Jido.*` namespace ownership and enforced dependency layers.

## Consequences

- Jido has one dependency graph, release unit, and startup tree.
- Startup order and supervision have one owner.
- A subsystem cannot use an OTP application boundary for internal isolation.
- Namespace and layer checks must preserve internal modularity.

## References

- [Jido package vision](../../../docs/package-vision.md)
- [Aspirational module dependency map](../../../docs/aspirational-module-dependency-map.md)
