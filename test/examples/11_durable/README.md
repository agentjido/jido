# Durable example tests

Run `mix test test/examples/11_durable --include example --seed 0 --warnings-as-errors`.

The [source overview](../../../examples/11_durable/README.md) defines ownership and limits.

- `11_01`: restore committed Agent state after SIGKILL.
- `11_02`: restore the current AgentServer Turn at step 6; confirmed steps do not repeat.
- `11_03`: restore the same Turn in a fresh BEAM with the DETS byte adapter.
- `11_04`: restore a topology member and its completed report Turn.

- `11_05`: restore saved completion after a lost storage reply.
- `11_06`: restore approval state and its absolute deadline between Turns.
- `11_07`: repeat a provider call with one operation ID and one publication.

Crash controls and barriers remain in test support. Child BEAM tests need local
sockets and `kill`, but no external service or credentials.

## Pending integration

11_08–11_19 have README-only test plans in matching folders. They add no tests
or coverage yet. Follow the
[integration checklist](../../../examples/11_durable/flow-control/INTEGRATION.md)
for the patched Action dependency, per-lesson gates, and proof order. Keep
11_01–11_07 green before promoting a new lesson. No skipped test skeletons are
part of this preparation.
