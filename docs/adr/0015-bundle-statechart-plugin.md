# ADR 0015 Bundle Statechart as a Jido Plugin

- Status: Accepted
- Date: 2026-11-21

## Context

The separate Statechart package already uses Jido Agent state, Signals,
Flows, and Plugin callbacks. Changes to those contracts can require a
coordinated Statechart release.

## Decision

Ship the chart API as `Jido.Statechart` and the Agent Plugin as
`Jido.Plugin.Statechart` in the `:jido` application. Give both namespaces
to the Statechart component in the capabilities layer. Keep W3C fixtures and
the runner in the opt-in ExUnit suite. The import uses Statechart commit
`f519203c8a6ff99902cf36b9248b67baa76e0a35`. The fixture files retain their
original contents and license.

## Consequences

Chart execution uses the same Turn and commit boundary as other Agent work.
The XML compiler uses OTP `:xmerl`. Basic HTTP sends use Req, which is already
in Jido's dependency tree. Users of the separate package must update the
Plugin and route module names when they move to core.

## References

- [Statechart guide](../../guides/built-in-plugins/statecharts.md)
- [Statechart obligations](../../test/contracts/jido.plugin/statechart.obligations.md)
- [W3C fixture license](../../test/fixtures/statechart/w3c/LICENSE)
