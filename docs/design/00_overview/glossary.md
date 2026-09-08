> Shared vocabulary proposal. This document is pending approval.

# Glossary

| Term | Meaning |
| --- | --- |
| Agent | A complete immutable domain value. |
| Agent definition | Static schemas, routes, Plugins, metadata, and behavior used to construct an Agent instance. |
| Agent Ref | Stable Agent identity across runtime lookup, storage, and transport. |
| Runtime location | Current process or node where an Agent runs. It is not durable identity. |
| Write authority | Permission for one activation to commit a durable Agent Record. |
| Turn | One selected Action or Flow and its input. |
| Executable output | Private complete state and Directive output from the selected Action or Flow. |
| Candidate Agent | Complete validated Agent proposed by one command. |
| Commit | The operation that makes a candidate Agent live. |
| Result | Tagged live reply that reports commit success or pre-commit failure. |
| Evaluation return | Direct `Agent.cmd/3` return. It proves no live or durable commit. |
| Turn Outcome | Runtime observation produced when one live Turn settles. |
| Directive | Typed description of external work that starts after commit. |
| Durable work intent | Portable pending work saved in Agent or Plugin state. |
| Plugin | Declared Agent capability with owned configuration and optional runtime work. |
| Plugin runtime | Supervised processes and resources for one Plugin instance. |
| Provider | Instance infrastructure behind a fixed core boundary. |
| Runtime topology | OTP processes and ownership below one Jido instance. |
| Topology control plane | Desired definitions, plans, repair, and live target management. |
