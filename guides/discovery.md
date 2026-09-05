# Explicit Agent definitions

V3 does not include the V2 Discovery service or its listing facade. Keep an
explicit application list of Agent modules or Topology definitions. Runtime
`list_agents` lists live registered Agents in an instance and partition; it is
not module discovery.

Use a trusted Codec Registry for schema and module references in stored authoring
data. Decoding strings must not create arbitrary atoms or load arbitrary modules.
See [authoring tests](../test/jido/agent/authoring_test.exs).
