# Agent values and state

An Agent definition has `id: nil` and `state: nil`. Call `MyAgent.agent()` or
`Jido.Agent.new/1` to create a definition. Call `MyAgent.new/1` or
`Jido.Agent.instantiate/2` to create an instance. The bang forms raise on error.
Instance options contain only `:id` and `:state`.

Declare a static data schema. The complete state includes Plugin-owned
keys. Unknown keys and invalid values fail validation. `Jido.Agent.set/2`
merges domain attributes and validates the complete result. An Action returns
a complete candidate state from `context.agent_state`.

Module restore uses the current module definition. Generic Agent checkpoints
retain their saved definition.

See the [complete example](../README.md#example) and
[authoring tests](../test/jido/agent/authoring_test.exs).

## Authoring extensions

Pass authoring extension modules with `use Jido.Agent, extensions: [MyExtension]`.
An extension can add entities to `agent do` and implement
`c:Jido.Agent.Extension.lower_agent/2`. Core collects its schema, routes and
Plugins first. It then calls each extension in declaration order with the
configuration and the remaining foreign entities.

Return `{:ok, config, remaining_entities}` or `{:error, exception}`. Every foreign
entity must be consumed. The resulting configuration still passes the normal
Agent validator. Generated route helpers use the final executable target, so
an extension can lower a reference to an Action or Flow before helper validation.
Duplicate extensions, unclaimed entities and invalid callback results fail.

Keep this work static. Do not start a process, run an Action, or contact a
service from a lowerer. Reuse the same semantic lowerer for data and Builder
frontends. Extensions do not change the Agent runtime or Plugin state rules.
