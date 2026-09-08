> Subsystem review index. This document is pending approval.

# 08 — Agent Server

Current comparison: [gap analysis](gap-analysis.md).

The Agent Server owns serialized Signal admission, active Turn control, live
Agent state, cancellation, commit coordination, Directive settlement, Plugin
runtime links, and runtime inspection.

Review [the Agent Server design](agent-server.md) against
`lib/jido/agent_server.ex` and the modules under `lib/jido/agent_server`.

Main alignment questions:

- Which Server API is public and which is internal?
- What are the exact runtime phases and control stages?
- Which work can be cancelled?
- How do admission, Turn, persistence, and Directive timeouts differ?
- What causes a controlled stop or an OTP restart?
- Which runtime status values are stable public contracts?
