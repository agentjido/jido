# Algebraic Effects and Jido

Date: April 11, 2026

This note is not claiming that Jido is a formal algebraic effects system.

Instead, it asks a narrower and more useful question:

What would algebraic effects mean in Jido terms, and where does the analogy help or break down?

## Short Answer

Jido already has a shape that resembles effect-oriented architecture:

- `Jido.Agent` keeps decision logic pure
- directives describe requested runtime work as data
- `Jido.AgentServer` interprets and executes those directives
- plugins and sensors extend what an agent can perceive or do without hard-coding everything into
  the agent module

That is not the same thing as algebraic effects in the language-theory sense, but it is close
enough to be a very useful design lens.

## The Helpful Mapping

Here is the most productive mapping between the two ideas.

### In algebraic effects

- a computation performs an effect operation
- a handler interprets that operation
- the pure logic stays separate from the runtime interpretation

### In Jido

- an agent returns directives
- the runtime executes those directives
- the agent's `cmd/2` can stay pure and deterministic

That makes Jido feel "effect-shaped" even though the mechanism is process-oriented and explicit
rather than built into the language runtime.

## Where the Analogy Fits Best

The analogy is strongest around directives.

For example:

- `%Jido.Agent.Directive.Emit{}` says "emit this signal"
- `%Jido.Agent.Directive.SpawnAgent{}` says "start this child agent"
- `%Jido.Agent.Directive.Schedule{}` says "run this later"

These look a lot like effect requests:

- the agent is not sending the signal itself
- the agent is not spawning the process itself
- the agent is not setting the timer itself

Instead, the agent returns a value that describes the requested effect, and the runtime handles it.

That is very close to the conceptual win that algebraic effects are trying to achieve.

## Why This Matters for Jido

This framing clarifies an architectural principle that is already present in the repo guidance:

- keep `cmd/2` pure
- keep directives for external effects
- do not use directives as disguised state mutation

From an effect-oriented point of view, that is exactly the right instinct.

The agent should decide what it wants to happen. The runtime should decide how that happens.

That separation buys Jido several things:

- easier testing of agent logic
- clearer runtime boundaries
- better traceability of side effects
- the option to interpret the same directive differently in different runtimes or tests

## A Concrete Jido Example

A pure agent can decide to notify someone without performing I/O directly:

```elixir
def cmd(agent, {:incident_detected, incident}, _ctx) do
  signal =
    Jido.Signal.new!("incident.alert", %{id: incident.id}, source: "/agent/system")

  directives = [
    Jido.Agent.Directive.emit(signal)
  ]

  {agent, directives}
end
```

That shape is important.

The agent is making a decision and returning a description of the effect. The actual side effect
happens later in the runtime.

## Where the Analogy Breaks

This is just as important as the mapping itself.

Jido is not a full algebraic effects system in the PL sense.

Key differences:

- Jido directives are explicit data structures, not language-level effect operations
- `Jido.AgentServer` is a runtime interpreter, not a lexical handler in the language
- there is no resumable continuation model exposed to agent code
- there is no typed effect row system
- there is no equational theory over directives in the formal sense
- effects happen across process boundaries and supervision trees, not just within one evaluation
  context

That means we should use algebraic effects as a design metaphor and architectural guide, not as a
claim about formal semantics.

## The Most Useful Lesson for Jido

The best takeaway is not "Jido should become an effect language."

It is:

Jido benefits when side effects are represented as explicit, typed requests that are interpreted by
the runtime rather than performed directly inside agent decision logic.

That principle already matches the project's architecture.

## Directives as an Effect Interface

One productive way to think about directives is:

- directives are the public effect vocabulary of the runtime
- `AgentServer` is the default interpreter for that vocabulary
- tests can substitute or observe that interpretation
- custom directives extend the effect vocabulary in an explicit way

This is a strong framing because it encourages better API design.

When a new runtime capability is needed, a good question becomes:

"Should this be a first-class directive with clear semantics?"

That question is healthier than pushing more hidden behavior into the runtime.

## Signals, State, and Effects

Jido also benefits from keeping three concerns distinct:

- signals are inputs and outputs in the communication model
- agent state is the pure decision context
- directives are requests for runtime side effects

That separation matters because effect systems become muddy when state transitions and external
effects are mixed together.

Jido's guidance against using directives for state mutation aligns with that concern.

## What This Suggests for Sensors

This lens is especially useful for the perception work we discussed earlier.

If attention control is treated as a runtime effect, then agents should be able to return explicit
requests such as:

- start a sensor
- stop a sensor
- reconfigure a sensor
- send a control event to a sensor

That leads naturally to directive-shaped APIs like:

- `StartSensor`
- `StopSensor`
- `SensorEvent`

This is one reason the sensor-attention proposal fits Jido well: it extends the runtime's effect
vocabulary rather than smuggling dynamic perception through hidden process messages or ad hoc state.

## A Healthy Boundary for Future Design

If Jido borrows from algebraic effects, the boundary should stay practical:

- keep agent logic pure
- keep effect requests explicit
- keep runtime interpretation centralized and observable
- avoid pretending directives are state transitions
- avoid over-claiming formal effect semantics that the runtime does not actually provide

That gives the design benefits of effect-oriented architecture without forcing Jido into a
completely different theoretical or language-level model.

## A Good Working Summary

The best concise statement is:

Jido is not an algebraic effects runtime, but its directive architecture already embodies one of
the most valuable ideas from algebraic effects: pure decision logic can return explicit descriptions
of desired side effects, and a separate runtime can interpret them.

That makes algebraic effects a useful conceptual framework for extending Jido, especially when
designing new directive families, runtime control surfaces, or dynamic sensor attention APIs.
