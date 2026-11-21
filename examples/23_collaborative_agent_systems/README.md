# 23 Collaborative Agent Systems

These examples show several ways that specialized Agents and role Flows can
complete one mission without a second orchestration runtime.

## Examples

1. [Incident-Response Organization](23_01_incident_response_organization/README.md).
2. [Specialist pipeline](23_02_specialist_pipeline/README.md).
3. [Manager and worker pool](23_03_manager_worker_pool/README.md).
4. [Research and publishing team](23_04_research_publishing_team/README.md).
5. [Service-operations team](23_05_service_operations_team/README.md).
6. [Nested organization](23_06_nested_organization/README.md).

The examples use deterministic local behavior. The research team is the
CrewAI-style comparison: roles remain normal Jido Agents, the coordinator owns
canonical mission state, parallel work has one reducer, and revision is
bounded.
