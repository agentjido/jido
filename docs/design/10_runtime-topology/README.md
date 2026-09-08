> Subsystem review index. This document is pending approval.

# 10 — Runtime topology and ownership

Current comparison: [gap analysis](gap-analysis.md).

Runtime topology owns the OTP shape below a Jido instance: Agent Servers,
Plugin runtime processes, bounded tasks, logical children, remote placement,
restart sources, and parent-death behavior.

Documents:

- [Runtime topology](runtime-topology.md)
- [Remote owned children](remote-owned-children.md)

Stable identity is a separate seam. See
[Stable Agent identity](../03_agent-identity/README.md).

Main alignment questions:

- Which process types belong in each runtime pool?
- How does a nonpersistent or persistent Agent restart?
- Which logical child relationships remain in core?
- What does explicit remote placement guarantee?
- Which placement, failover, and fencing policy belongs to another package?
