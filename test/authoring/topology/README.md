# Topology authoring corpus

Eleven saved cases use 12 source variants and six authoring forms. The minimal case
has both keyword and block variants. See the [suite guide](../README.md) for
commands and shared rules.

| Case | Main checks |
| --- | --- |
| Minimal | Keyword and block equality, initial state |
| Counted group | Default and zero count, member index, group dependencies, Agent limit |
| Keyed group | Stable IDs, escaped keys, reordered and empty input, duplicate keys |
| Ownership | Parent links, parent-exit policy, dependency layers |
| Bus | Resource declaration, subscription, startup order |
| Nested component | Input binding, bus import, public export, scoped IDs, private references |
| Repeated components | Shared child and Bus, separate inputs, escaped component IDs, inclusion order |
| Deep composition | Two include levels, Agent/group/Bus re-exports, empty group, exact child limit |
| Configured | Remote placement, all startup settings, Bus options, all ownership policies |
| Plugin | Plan contributions for a single Agent and a group, unchanged source definition |
| Combined host | Owner Agent, Topology extension, lowered declarations, separate constructors |

## Assertions

`authoring_test.exs` compares each form with independent declaration data and
a saved JSON document. It checks three JSON round trips, trusted Registry
references, all instance constructors, normalized inputs, and complete
`Jido.Topology.Plan` values. Expected plans include IDs, initial state,
ownership, subscriptions, dependency layers, lookups, and component counts.
Invalid inputs must return structured errors. Later valid inputs must still
produce the same plan.

`boundaries_test.exs` checks invalid source, graph errors, empty plans, Builder
reuse, reserved Bus options, startup values, ownership policies, remote Bus
subscriptions, and combined Agent/Topology behavior.

`composition_boundaries_test.exs` checks sibling ownership cycles, exact import
bindings, private endpoints, export kinds, nested input error paths, inclusion
order, and child limits after JSON transport.

`plugin_boundaries_test.exs` checks 13 failure modes across all six forms:
raise, throw, exit, invalid callback result, invalid contribution shape, wrong
package identity, invalid entry, reserved Bus config, duplicate resource,
missing endpoint, ownership cycle, duplicate ownership, and explicit rejection.
It checks structured errors, earlier contribution isolation, unchanged JSON,
retries, and a valid plan before and after failure. Group and included
declarations also exercise callback failures. Fault JSON is derived in these
tests for transport checks; the 11 saved documents remain separate expectations.

`metadata_test.exs` checks atom, string, and mixed keys across forms, plus invalid
maps, structs, and runtime values.

## Layout

Topology support lives in `../support/topology/`, under the
`JidoTest.Authoring.Topology` namespace:

- `fixtures/*.exs` contains valid source modules and shared fixture dependencies.
- `fixtures/invalid/` contains source that must fail compilation.
- `fixtures/json/` contains 11 reviewed version-2 Topology documents.
- `corpus.exs` loads selected fixtures and constructs each form.
- `cases.exs` holds independent declarations, input cases, and plans.

Test files stay in this folder.

To add a case, add its source, a Corpus variant, a Cases clause, and a saved
JSON document. Supply complete expected plans. Do not derive expected values
from `Plan.build/3` or rewrite snapshots during tests.

These are pure authoring tests. They do not start a Topology controller, bus,
or AgentServer. Runtime lifecycle and distributed behavior remain outside this
suite.

`Plan.resolve/4` produces a member key, not proof that a group member exists.
The test checks the key and the separate plan lookup. A child Agent-limit
error currently names `startup.max_agents` but does not include a component
path. Nested input errors do include the component paths and their causes.
