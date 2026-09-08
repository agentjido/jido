> Subsystem review index. This document is pending approval.

# 01 — Agent

Current comparison: [gap analysis](gap-analysis.md).

`Jido.Agent` owns immutable Agent definitions and instances, domain state,
Plugin-owned state composition, schemas, routes, metadata, checkpoints, and
direct command evaluation.

Review [the Agent design](agent.md) against `lib/jido/agent.ex` and the modules
under `lib/jido/agent`.

Main alignment questions:

- Does one Agent type represent both a neutral definition and an instance?
- Does Plugin state remain inside the complete Agent state map?
- Which replacement and state access functions are public?
- Which checkpoint behavior belongs to Agent modules and which belongs to core?
- How does a definition revision bind code, schemas, routes, and Plugins?
