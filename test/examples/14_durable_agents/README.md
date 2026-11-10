# 14 Durable Agent Tests

Run `mix test test/examples/14_durable_agents --include example --seed 0 --warnings-as-errors`.

The [source overview](../../../examples/14_durable_agents/README.md) defines ownership and limits.

- `14_01`: restore committed Agent state after SIGKILL.
- `14_02`: restore the current AgentServer Turn at step 6; confirmed steps do not repeat.
- `14_03`: restore the same Turn in a fresh BEAM with the DETS byte adapter.
- `14_04`: restore a topology member and its completed report Turn.

- `14_05`: restore saved completion after a lost storage reply.
- `14_06`: restore one suspended approval Flow and its absolute wait deadline.
- `14_07`: repeat a provider call with one operation ID and one publication.

Crash controls and barriers remain in test support. Child BEAM tests need local
sockets and `kill`, but no external service or credentials.

## Pending integration

Lessons 14_08–14_19 are proposal-only source documents. They are excluded from
the supported example and test trees, and they add no coverage. The source
manifest records the exclusion. Keep 14_01–14_07 green before a new lesson is
promoted. This test tree has no skipped proposal skeletons.
