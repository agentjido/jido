> Seam alignment evidence. The four-owner implementation direction was selected
> on 2026-09-09. The full target design is still pending approval.

# Plugin alignment

## Status

- Implementation reviewed: 2026-09-09 on branch `v3-spike`.
- Prerequisites: package boundaries, portable error values, Agent state,
  authoring order, Agent identity, and source-Signal Turn selection are present.
- Alignment state: `Implemented with deferred owner integrations`.

The Plugin package and its four owner facets are implemented. Agent and Agent
Server use their facets now. Persistence and Topology have bounded conversion
APIs. Their record and plan call sites stay with seams 07 and 11. The coherent
runtime bootstrap value stays with seam 08.

This execution state is not approval of all requirements in the target design.

## Selected architecture

One Agent declaration still contains an ordered list of package modules or
`{module, keyword_options}` pairs. A new package is callback-free:

```elixir
defmodule MyApp.Capability do
  use Jido.Plugin,
    agent: MyApp.Capability.Agent,
    agent_server: MyApp.Capability.Server,
    persistence: MyApp.Capability.Persistence,
    topology: MyApp.Capability.Topology,
    vsn: 1,
    option_keys: [
      agent: [:fields],
      agent_server: [:endpoint],
      persistence: [:format],
      topology: [:bus]
    ]
end
```

`Jido.Plugin.Manifest` holds only static package metadata. Normalization builds
one private aggregate Spec and up to four private owner Specs. An owner Spec
does not contain fields from another owner.

| Owner | Public behavior | Authority |
| --- | --- | --- |
| Agent | `Jido.Agent.Plugin` | Pure preparation, owned state, and owned Directives |
| Agent Server | `Jido.AgentServer.Plugin` | Live admission, one runtime root, readiness, outbound preparation, and post-commit dispatch |
| Persistence | `Jido.Persistence.Plugin` | Pure dump and load of one paired owned-state value |
| Topology | `Jido.Topology.Plugin` | Pure contribution of current canonical Bus, ownership, and subscription entries |

`use Jido.Plugin` with no options remains the mixed compatibility behavior.
The normalizer classifies its known callbacks with an explicit legacy path.

## Canonical source

| Source | Implemented contract |
| --- | --- |
| `lib/jido/plugin.ex` | Small package declaration entry and legacy compatibility facade. A new package cannot define facet callbacks. |
| `lib/jido/plugin/manifest.ex` | Closed owner list, positive package version, static common options, and checked option-to-facet mapping. |
| `lib/jido/plugin/normalizer.ex` | Package or legacy detection, owner-Spec construction, duplicate ownership checks, callback authority checks, and pairing rules. |
| `lib/jido/agent/plugin.ex` | Agent schema composition, bounded preparation, state protection, contribution, owned state validation, and Directive validation. |
| `lib/jido/agent/plugin/preparation.ex` | Validated source and effective Signals, declared domain projection, owned state, caller context, and owned prepared input. |
| `lib/jido/agent/plugin/transition.ex` | Validated before and after projections, owned state and input, and owned executable Directives. |
| `lib/jido/agent/plugin/contribution.ex` | Validated unchanged-or-replace state result and appended owned Directives. |
| `lib/jido/agent_server/plugin.ex` | Live callback execution, reverse outbound preparation, child-Spec validation, readiness, and dispatch. |
| `lib/jido/persistence/plugin.ex` | Pure owned-value dump and load, portable output checks, context identity checks, and loaded-state schema checks. |
| `lib/jido/persistence/plugin/context.ex` | Validated package version, record format, direction, and reason. It has no adapter or record authority. |
| `lib/jido/topology/plugin.ex` | Pure contribution execution and validation through current canonical Topology entry validators. |
| `lib/jido/topology/plugin/context.ex` | Validated package version and static Agent identity. It has no controller or activation authority. |
| `lib/jido/topology/plugin/contribution.ex` | Validated lists for Bus resources, ownership relationships, and Bus subscriptions only. |
| `lib/jido/agent/command/runner.ex` | Source-Signal selection before preparation, package-keyed `context.plugin_inputs`, state protection, and ordered contribution. |
| `lib/jido/agent_server.ex` | Direct use of Agent Server facet admission, outbound preparation, runtime lookup, and dispatch. |

`Jido.Plugin.Spec` and all owner Specs have `@moduledoc false`. They are not
ecosystem contracts.

## Ownership results

### Agent

The Agent facet receives no complete Agent. `observes/1` selects top-level
domain fields. `Jido.Agent.Plugin.Preparation` includes only that projection,
the package-owned state value, the source and effective Signals, bounded caller
context, and the package-owned prepared input.

Each package has a separate key in `context.plugin_inputs`. A later facet does
not receive an earlier package input. Route selection stays fixed from the
source Signal. Preparation can change the effective Signal but cannot select a
new executable.

After executable success, the facet receives a bounded Transition. It can
return `:unchanged` or one complete owned-state replacement. It can append only
Directive types that its Agent facet owns. Complete candidate validation still
runs after all contributions.

### Agent Server

The Agent Server facet owns the callbacks that need live data. Admission stays
in declaration order. Outbound preparation stays in reverse declaration order.
The existing permanent-child, readiness, runtime-unavailable, task timeout,
post-commit, and failure-settlement rules do not change.

The package module is not the runtime callback module for new packages. Runtime
children use the package as the child identity and the Agent Server facet as
the callback module.

### Persistence

The Persistence facet can receive only one owned state value, a validated
`Jido.Persistence.Plugin.Context`, and its mapped static options. Dump output
must be portable. Load output must be portable and valid for the paired Agent
facet state schema. A Persistence facet requires a stateful Agent facet.

This seam does not call the facet from checkpoint record assembly. Seam 07 owns
that order and the compatibility rule for complete custom checkpoints.

### Topology

The Topology facet can receive only a validated static context and its mapped
options. Its contribution can contain current canonical Bus resources,
ownership relationships, and Bus subscriptions. The standard Topology entry
validator checks each value.

This seam does not add the contribution to a complete definition or plan.
Seam 11 owns lowering order, duplicate checks, limits, and activation.

## Executable evidence

| Evidence | Result |
| --- | --- |
| `test/jido/plugin/facets_test.exs` | A callback-free package normalizes to four separate owner Specs. Agent preparation and contribution work. Live dispatch, Persistence conversion, and Topology contribution use owner values. Invalid owners, option mappings, Persistence results, contexts, loaded state, and Topology entries fail. |
| `test/jido/plugin/preparation_test.exs` | Preparation receives only declared domain state and owned Plugin state. Read-only fields cannot change. Prepared input must be portable. |
| `test/examples/99_research/99_10_plugin_isolation/plugin_isolation_test.exs` | All four research assertions run. Projection and prepared-input isolation checks are no longer skipped. |
| Existing Plugin contract, validation, result, order, and runtime tests | The mixed callback compatibility contract remains stable. |
| Full Core suite | All non-example tests passed after the split. |

## Requirement disposition

| Requirement set | State | Evidence or owner |
| --- | --- | --- |
| `PLG-REQ-001` to `PLG-REQ-010` | `Proven` | Ordered declarations, manifest validation, owner Specs, and Codec-compatible canonical declarations. |
| `PLG-REQ-011` to `PLG-REQ-017` | `Proven` | Combined schema, unique state ownership, protected executable output, owned contribution, schema checks, and portable values. |
| `PLG-REQ-018` to `PLG-REQ-029` | `Proven` | Source-Signal route selection, ordered live admission, bounded preparation, and package-keyed inputs. |
| `PLG-REQ-030` to `PLG-REQ-039` | `Proven` | Bounded Transition and Contribution values, ordered append, unique Directive ownership, and Agent/Server pairing. |
| `PLG-REQ-040` to `PLG-REQ-046`, `PLG-REQ-049` to `PLG-REQ-052` | `Proven` | Existing post-commit and runtime lifecycle suites plus owner-module routing. |
| `PLG-REQ-047`, `PLG-REQ-048` | `Deferred to seam 08` | `Jido.Plugin.Init` still needs one committed owned-state and state-version pair for first start and replacement. |
| `PLG-REQ-053` to `PLG-REQ-057` | `Facet proven; integration deferred to seam 07` | Direct conversion, context, portability, and paired-schema tests pass. Record integration is not present. |
| `PLG-REQ-058` | `Deferred to seam 07` | The custom complete-checkpoint bypass belongs to the Persistence owner. |
| `PLG-REQ-059`, `PLG-REQ-060` | `Facet proven; integration deferred to seam 11` | Direct canonical contribution tests pass. Definition and plan integration is not present. |
| `PLG-REQ-061` to `PLG-REQ-076` | `Proven for compatibility form` | Existing Scheduler occurrence, durability, and recovery tests stay unchanged. |

## Compatibility and migration

No removal occurs in this seam.

- Existing module and `{module, options}` declarations keep their order and
  Codec form.
- Existing built-ins can continue to use the mixed `Jido.Plugin` behavior.
- Legacy `prepare/2`, bounded `prepare_turn/2`, `update_state/3`, live
  callbacks, child Specs, and current error messages have explicit paths.
- New packages must use owner facets. The package module cannot contain facet
  callbacks.
- Plugin-owned state stays as one top-level field in the complete Agent state.
- `Jido.Plugin.state/2` remains available during runtime bootstrap migration.
- Scheduler occurrence IDs and durable state meaning do not change.

## Remaining owner work

| Seam | Required follow-up |
| --- | --- |
| 07 Persistence | Call Persistence facets during the approved default checkpoint path. Preserve the complete custom-checkpoint compatibility rule. |
| 08 Agent Server | Add committed owned state and the matching state version to one immutable runtime Init value for first start and replacement. |
| 11 Topology control plane | Lower Topology facet contributions through the Topology owner before complete plan validation. |
| 99 Delivery | Migrate built-ins and add a public-only package fixture before legacy removal is considered. |

## Completion gate for this seam

- [x] One callback-free package selects no more than four closed owner facets.
- [x] One declaration produces separate Specs with no foreign fields.
- [x] Direct Agent use needs only the Agent facet.
- [x] Plugin state, prepared input, projections, and Directives have ownership
      and portable-value proof.
- [x] Agent Server live callbacks route through its owner module.
- [x] Persistence and Topology facets have bounded public values and direct
      failure proof.
- [x] Supported mixed behavior remains explicit.
- [ ] Runtime bootstrap integration is complete in seam 08.
- [ ] Persistence record integration is complete in seam 07.
- [ ] Topology plan integration is complete in seam 11.
- [ ] The full target design has user approval.
