# Prepared serialization contract

The prepared source uses `Jido.Agent` and `Jido.AgentServer`.

- Persistence keys start with `jido:agent:v1:`. The envelope uses `format: 1`,
  `kind: :agent`, `agent_module`, and `agent_id`. It is a new Agent format.
- Actor records used `jido:actor:v1:`, `kind: :actor`, `actor_module`, and
  `actor_id`. Normal Agent loads do not look up those keys. An old envelope
  moved under a new key is rejected. There is no automatic Actor or core V2
  record migration.
- Authoring JSON uses `type: "jido.agent"` and `version: 1`. Registry categories
  use `:agent`. Topology documents use `agents` and Agent node kinds.
- Runtime snapshots use `agent`. Command and Plugin contexts use `agent_id`,
  `agent_state`, and `agent_server`. Messages and telemetry use Agent names.
- Erlang term checkpoints contain module atoms. A schema or domain module
  renamed in this preparation can also change a stored term. Applications must
  export validated data with the old source, apply an explicit conversion,
  and save it with the new source. Do not rewrite opaque bytes in place.

These names do not provide core V2 API compatibility. Builder, Codec, child
ownership, and Topology remain implemented. The Ref facade, Plugin pipeline,
and new persistence architecture in `docs/design` remain proposals.

A Redis conditional-write transport error now returns
`{:error, {:indeterminate, reason}}`. A malformed Redis write reply has the same
outer tag. These results stop the current writer. A returned adapter error that
is not marked indeterminate must confirm that the proposed value was not saved.
An exception or malformed adapter callback result is also uncertain. A new
activation must restore authoritative storage before more work can run.
