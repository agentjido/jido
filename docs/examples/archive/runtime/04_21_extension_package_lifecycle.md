> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Extension Package Lifecycle

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_21_extension_package_lifecycle`
- **Status:** doesn't work yet
- **Complexity level:** 4 - Runtime capability
- **Feature group:** runtime
- **Test class:** local deterministic

## Profile

- **Purpose:** Load, start, reload, and stop one explicit Agent capability bundle without changing domain composition.
- **User story:** As an application owner, I enable one trusted capability for selected Agents and can replace or remove it safely.
- **Trigger or input:** Actor startup options and explicit install, reload, or remove Signals.
- **Agent state:** Domain state has no extension internals. Runtime state records capability ID, version, configuration digest, owned child references, and lifecycle status.
- **Actions or Flow:** Normal Signals still select one declared Action or Flow. The capability can add runtime handlers and input adapters, but it cannot inject hidden domain steps.
- **External interactions:** A local fake package manifest and supervised fake runtime process.
- **Runtime Directives or capabilities:** Typed install, reload, and remove commands control one supervised runtime capability.
- **Expected result:** Installation is idempotent, conflicts are deterministic, initialization finishes before use, reload does not change an active Turn, and removal closes all owned resources.
- **Failure cases:** Invalid manifest, duplicate capability, bad configuration, initialization failure, child crash, partial reload, unsupported version, or removal with active work.
- **Jido features under pressure:** Runtime capability discovery, configuration validation, child supervision, ownership, lifecycle ordering, isolation, and explicit composition.
- **Source framework and links:** [Pi extensions](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md), [Pi packages](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/packages.md), and [Pi Package Catalog](https://pi.dev/packages)

## Smallest missing contract

Jido can declare Plugins on an Actor module, but it does not have a small public
contract for a capability that can be selected, versioned, reloaded, and removed
at runtime. This test must not require generic Turn middleware.


## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/runtime/04_21_extension_package_lifecycle/extension_package_lifecycle.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/runtime/04_21_extension_package_lifecycle/extension_package_lifecycle_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: SDK contract.
- Remaining work: The local manager validates lifecycle data. Live versioned capability install, reload, and removal are not public Actor runtime operations.

An example-scope gap is not evidence of a core Jido defect.
