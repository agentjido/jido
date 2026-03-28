---
id: jido.spec_subject_map
status: accepted
date: 2026-03-28
affects:
  - repo.governance
---

# Jido Spec Subject Map

## Context

The Jido release now spans a broad current-truth surface: pure agents and
actions, runtime hosting and hierarchy, plugins and sensors, persistence,
observability, Pods, mutable topology, and partition-based multi-tenancy.

That surface is too large to leave captured only in a package-level spec plus a
handful of ad hoc notes. We need a stable authored subject map that:

- groups the package into user-facing domains instead of individual files
- covers the full repository surface so frontier status is meaningful
- links each domain to durable docs and executable proof
- stays maintainable as the release evolves

## Decision

Jido current truth is organized as a package-level subject plus a set of stable
domain subjects:

- agents and actions
- signals and directives
- strategies
- runtime lifecycle
- plugins and sensors
- runtime persistence
- thread, memory, and identity
- observability and tracing
- debugging and errors
- Pods
- multi-tenancy
- testing and examples
- configuration and discovery
- worker pools and tooling
- integrations and migration

Each subject should:

- define a stable user-facing contract in `.spec/specs/*.spec.md`
- claim a broad `surface` that covers the relevant source, guides, and tests
- use guide-backed verification for durable conceptual claims when stable
  `covers:` markers are practical
- use targeted `kind: command` verification for behavioral proof

Cross-cutting expansions or reorganizations of this subject map should be
captured as ADR updates under `.spec/decisions/`.

## Consequences

The spec workspace now reflects the real Jido product surface instead of only
the bootstrap scaffold, which makes release-time coverage and drift review much
more useful.

The tradeoff is that broad current-truth changes will often become
cross-cutting branch updates and should carry an ADR when they materially
change how the subject map is organized.

Future specs should prefer extending one of these domains before introducing a
new subject, unless the package grows a clearly separate user-facing contract.
