# Signals And Directives

Current-truth contract for routed signals, explicit directives, internal state operations, and scheduling effects.

## Intent

This subject covers how Jido moves messages through the system, how effects stay explicit, and how scheduling-related effects remain part of the directive/runtime boundary rather than ad hoc process messaging.

```spec-meta
id: jido.signals_and_directives
kind: subsystem
status: active
summary: Jido routes signals, models side effects as directives, and keeps state operations internal to strategy execution.
surface:
  - guides/signals.md
  - guides/directives.md
  - guides/state-ops.md
  - guides/scheduling.md
  - lib/jido/agent/directive.ex
  - lib/jido/agent/directive
  - lib/jido/agent/state_op.ex
  - lib/jido/agent/state_ops.ex
  - lib/jido/agent/schedules.ex
  - lib/jido/agent_server/signal_router.ex
  - lib/jido/agent_server/directive_exec.ex
  - lib/jido/agent_server/directive_executors.ex
  - lib/jido/scheduler.ex
  - lib/jido/scheduler
  - test/examples/signals
  - test/examples/runtime/schedule_directive_test.exs
  - test/jido/agent/directive
  - test/jido/agent/directive_test.exs
  - test/jido/agent/schedules_integration_test.exs
  - test/jido/agent/schedules_test.exs
  - test/jido/agent/state_op_test.exs
  - test/jido/agent/state_ops_test.exs
  - test/jido/agent_server/directive_exec_test.exs
  - test/jido/agent_server/signal_router_test.exs
  - test/jido/agent_server/cron_integration_test.exs
  - test/jido/agent_server/cron_tick_delivery_test.exs
```

## Requirements

```spec-requirements
- id: jido.signals_and_directives.signal_routing
  statement: Jido shall route CloudEvents-style signals to agent behavior through typed routing rules instead of ad hoc process messages.
  priority: must
  stability: stable

- id: jido.signals_and_directives.directive_effect_boundary
  statement: Jido shall represent external effects as directives executed by the runtime rather than hidden mutations inside pure agent code.
  priority: must
  stability: stable

- id: jido.signals_and_directives.state_ops_internal_mutation
  statement: Jido shall keep non-trivial state mutation inside strategy-applied state operations instead of treating them as external directives.
  priority: must
  stability: stable

- id: jido.signals_and_directives.scheduling_support
  statement: Jido shall support scheduling, cron delivery, and cancellation through explicit directive and runtime flows.
  priority: must
  stability: stable
```

## Verification

```spec-verification
- kind: guide_file
  target: guides/signals.md
  covers:
    - jido.signals_and_directives.signal_routing

- kind: guide_file
  target: guides/directives.md
  covers:
    - jido.signals_and_directives.directive_effect_boundary
    - jido.signals_and_directives.scheduling_support

- kind: guide_file
  target: guides/state-ops.md
  covers:
    - jido.signals_and_directives.state_ops_internal_mutation

- kind: command
  target: mix test test/jido/agent/directive_test.exs test/jido/agent/directive/cron_test.exs test/jido/agent/directive/cron_cancel_test.exs test/jido/agent/schedules_test.exs test/jido/agent/schedules_integration_test.exs test/jido/agent/state_op_test.exs test/jido/agent/state_ops_test.exs test/jido/agent_server/signal_router_test.exs test/jido/agent_server/directive_exec_test.exs test/jido/agent_server/cron_integration_test.exs test/jido/agent_server/cron_tick_delivery_test.exs test/examples/signals/signal_routing_test.exs test/examples/signals/context_aware_routing_test.exs test/examples/signals/emit_directive_test.exs test/examples/runtime/schedule_directive_test.exs
  execute: true
  covers:
    - jido.signals_and_directives.signal_routing
    - jido.signals_and_directives.directive_effect_boundary
    - jido.signals_and_directives.state_ops_internal_mutation
    - jido.signals_and_directives.scheduling_support
```
