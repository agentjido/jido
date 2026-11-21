# ADR 0012 Agent route input preparation

- Status: Accepted
- Date: 2026-11-19

## Context

An Agent can set policy on its root AI Flow. A custom Flow can read request parameters at its first step. Policy must apply before that read in direct and live commands.

## Decision

The Agent runner calls the optional Plugin route input callback after route selection and default merge. Each callback receives the normalized request and current parameters. It returns parameters for executable validation. The Agent runner retains control of the route, Signal, context, and state. The AI Plugin owns policy for the AI request route. AI preflight uses the same policy function.

## Consequences

Agent commands keep the selected Flow as their execution target. Standalone Flows use their normal input validation. Stored continuations keep their existing input.

## References

- [Plugin callbacks](../../lib/jido/plugin.ex)
- [Agent runner](../../lib/jido/agent/runner.ex)
- [AI request policy](../../lib/jido/ai/request_policy.ex)
