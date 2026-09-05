# Agent values and state

An Agent definition has `id: nil` and `state: nil`. Call `MyAgent.agent()` or
`Jido.Agent.new/1` to create a definition. Call `MyAgent.new/1` or
`Jido.Agent.instantiate/2` to create an instance. The bang forms raise on error.
Instance options contain only `:id` and `:state`.

Declare a static `Zoi.object` schema. The complete state includes Plugin-owned
keys. Unknown keys and invalid values fail validation. `Jido.Agent.set/2`
merges domain attributes and validates the complete result. An Action returns
a complete candidate state from `context.agent_state`.

Set `max_state_size: bytes` on a definition, in `use Jido.Agent`, through
`Builder.max_state_size/2`, or in the `agent` block. The default is `nil`.
The size is `:erlang.external_size(state)`, including Plugin state. It is not
heap size. The smaller module and definition limits apply. Construction,
validation, transition, command output, restore, and live commit check the limit.
An oversized result returns `Jido.Error.ValidationError` with `kind: :state_size`,
`subject: :state`, and the actual and maximum sizes. It does not commit or
execute its directives. A nil limit avoids the size calculation.

Codec documents retain a non-nil limit in the optional `max_state_size` field.
Module restore uses the current module definition. Generic Agent checkpoints
retain their saved definition. A module limit still applies to a manually
changed struct. A byte limit does not make nonportable data safe to store.

See the [complete example](../README.md#example) and
[authoring tests](../test/jido/agent/authoring_test.exs).
