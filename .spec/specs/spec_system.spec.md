# Spec System

This subject defines the contract for the `.spec` workspace itself.

```spec-meta
id: spec.system
kind: policy
status: active
summary: Canonical workspace contract for authored specs and generated Spec Led state.
surface:
  - .spec/README.md
  - .spec/AGENTS.md
  - .spec/decisions/README.md
  - .spec/specs/*.spec.md
  - .spec/decisions/*.md
```

## Requirements

```spec-requirements
- id: spec.workspace.readme_present
  statement: The repository shall include a .spec/README.md that explains purpose, layout, and workflow.
  priority: must
  stability: stable

- id: spec.workspace.agents_present
  statement: The repository shall include a .spec/AGENTS.md that gives local operating guidance for agents working inside the .spec workspace.
  priority: must
  stability: stable

- id: spec.workspace.agent_prime_context
  statement: The repository shall include a .spec/AGENTS.md that tells agents to start a session with mix spec.prime before editing current truth.
  priority: should
  stability: evolving

- id: spec.workspace.decisions_readme_present
  statement: The repository shall include a .spec/decisions/README.md that explains when durable ADRs belong in the workspace.
  priority: must
  stability: stable

- id: spec.workspace.state_generated
  statement: When indexing and validation run, the workspace shall generate .spec/state.json containing indexed subjects, indexed decisions, and verification state.
  priority: must
  stability: stable
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/README.md
  covers:
    - spec.workspace.readme_present

- kind: source_file
  target: .spec/AGENTS.md
  covers:
    - spec.workspace.agents_present
    - spec.workspace.agent_prime_context

- kind: source_file
  target: .spec/decisions/README.md
  covers:
    - spec.workspace.decisions_readme_present

- kind: command
  target: mix spec.index
  covers:
    - spec.workspace.state_generated

- kind: command
  target: mix spec.validate
  covers:
    - spec.workspace.state_generated
```
