# ADR 0018 Stateless AI browser tools

- Status: Accepted
- Date: 2026-11-21

## Context

A ReAct Agent can need to find public sources and read their text. The AI
Plugin already prepares the Agent's tools and carries trusted inputs into
Action execution.

## Decision

Add an optional browser declaration to the AI Plugin. Lower it to portable
allow and exposure data, then prepare the selected static Actions through the
existing tool path. Keep the provider key in host runtime configuration. Apply
both allowlists to page URLs and check the address before each pinned
connection. Use bounded HTTP requests for search and page reading.
Keep plain text as the default fetch format. Allow the host to select
Markdown from the optional Html2Markdown dependency. Apply the same byte
limits to both formats.

## Consequences

The feature uses the existing request tool policy and tool result projection.
The browser block needs no Agent runtime state. Jido Browser continues to
provide session and rendering workflows.

## References

- [Browser tools guide](../../guides/ai/basic-web-browser.livemd)
- [AI tools obligations](../../test/contracts/jido_ai/tools.obligations.md)
