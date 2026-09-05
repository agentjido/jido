# Instance configuration

Put a named Jido instance under your application's supervisor. A module can use
`Jido` with `otp_app` and optional `persistence` configuration. Explicit instance
names keep Registries, task supervisors, Bus scope, and runtime stores separate.

Agent definitions hold static schema, routes, metadata, and Plugin declarations.
Instance construction supplies identity and initial state. Server startup uses
`initial_state`, not `state`, for that override. A prebuilt Agent instance cannot
also receive identity or initial-state overrides.

Set runtime limits through `Jido.AgentServer.Options`: admission capacity,
directive count, execution and directive timing, and idle lifecycle options.
A runtime limit is not a durable-work policy. Check each option's API schema.

See [instance tests](../test/jido/instance_test.exs) and
[startup validation](../test/jido/agent/startup_test.exs).
