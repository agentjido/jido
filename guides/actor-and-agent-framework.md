# Actors, Agents, and Jido

Jido is an actor and agent framework for Elixir. It joins an immutable domain
model with OTP process ownership.

An Agent is data. It contains a definition, an identity, validated state,
routes, and declared Plugins. `Jido.Agent.cmd/3` applies one Signal and returns
a candidate Agent value. This operation does not start or own a process.

An Agent Server is the live actor. It owns one Agent instance in an OTP
process, accepts serial Turns, commits state, and dispatches effects. The actor
has a mailbox, lifecycle, supervision, and runtime resources.

## The Main Boundary

```text
Signal
  -> prepare and route
  -> run one Action or Flow
  -> validate one complete candidate
  -> persist and commit
  -> dispatch Directives
  -> settle the Turn
```

The Agent decides what the next domain state can be. The Agent Server decides
when that state becomes live. OTP supplies process isolation, messages,
monitors, timers, and supervision.

## Why Keep Both Forms

The value form gives you explicit state transitions. You can construct,
validate, serialize, test, and compare Agents without starting processes.

The actor form gives you runtime ownership. It serializes concurrent input,
owns Plugin processes, maintains child relationships, applies admission rules,
and records one committed revision at a time.

Do not put PIDs, monitors, task handles, timers, or client connections in Agent
state. Put them in a Plugin runtime or another supervised process.

## What A Turn Guarantees

A successful Turn commits one complete Agent state. It advances the state
version once. A failed Turn preserves the prior committed state.

A Turn is not an external transaction. An Action can complete I/O before a
later validation error. A Directive can fail after the state commit. Jido
cannot undo such work. Applications must use idempotency keys and recovery
rules for external systems.

## How Jido Uses Its Packages

[Jido Action](https://hexdocs.pm/jido_action/) defines Actions, Instructions,
Flows, and the execution boundary. Jido uses these values as the behavior for
one Agent Turn.

[Jido Signal](https://hexdocs.pm/jido_signal/) defines the Signal envelope,
routing, dispatch, and Bus. Jido uses Signals as typed actor messages.

Core Jido adds Agent state, Agent Server processes, Plugins, Directives,
persistence, owned children, and static topologies.

## Choose The Smallest Useful Layer

- Use an Action when one validated operation is sufficient.
- Use a Flow when one call needs several dependent operations.
- Use a direct Agent command when you want an explicit value transition.
- Use an Agent Server when you need a live actor with serial state.
- Use child Agents when one actor owns a dynamic set of workers.
- Use a Topology when an application has a static actor system to activate.

Next, read [Agent Definitions And Instances](agent-definitions-and-instances.md)
and [Turns, Commit, And Effects](turns-commit-and-effects.md).
